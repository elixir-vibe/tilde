defmodule Tilde.Session.AgentLoop do
  @moduledoc "Session-owned assistant loop: start, stream, cancel, and record semantic events."

  alias Tilde.Core.{AgentRuntime, Event, Session}
  alias Tilde.Runtime.{JidokaEvent, LLM, RateLimit}
  alias Tilde.Session.AgentLoop.{Prompt, State}
  alias Tilde.Tool.Event, as: ToolEvent

  @type server_state :: map()
  @type emit_fun :: (server_state() -> term())

  @spec maybe_resume(server_state(), emit_fun()) :: server_state()
  def maybe_resume(%{session: %Session{} = session} = state, emit) do
    runtime = Session.agent_runtime(session)

    with true <- LLM.enabled?(),
         true <- resumable_runtime?(session, runtime) do
      resume(state, runtime, emit)
    else
      _other -> state
    end
  end

  @spec maybe_start(server_state(), Session.t(), emit_fun()) :: server_state()
  def maybe_start(%{session: %Session{} = session} = state, %Session{} = previous, emit) do
    with true <- LLM.enabled?(),
         true <- new_input_submitted?(previous, session),
         {index, %Event{} = event} <- latest_input_submission(session) do
      prompt = Prompt.new(index, event)

      if State.active?(state.agent_loop) do
        enqueue_prompt(state, prompt)
      else
        maybe_start_rate_limited(state, prompt, emit)
      end
    else
      _other -> state
    end
  end

  @spec cancel(server_state(), emit_fun()) :: server_state()
  def cancel(state, emit) do
    cancel_checkpoint(state.agent_loop.runtime)
    cancel_task(state.agent_loop.task)

    state
    |> update_session(
      &Session.append_event(
        &1,
        Tilde.assistant_turn_cancelled(block_id: state.agent_loop.block_id)
      )
    )
    |> clear_runtime()
    |> emit_then(emit)
  end

  @doc false
  @spec handle_task_exit(server_state(), pid(), term(), emit_fun()) :: server_state()
  def handle_task_exit(state, task, reason, emit) do
    cond do
      not State.matches_task?(state.agent_loop, task) ->
        state

      reason == :normal and AgentRuntime.resumable?(state.agent_loop.runtime) ->
        cancel_task_timer(state.agent_loop.timeout_timer)
        put_agent_loop(state, State.task_stopped(state.agent_loop))

      true ->
        failure = {:agent_task_exit, reason}

        state
        |> update_session(fn session ->
          session
          |> Session.append_event(Tilde.assistant_done(llm_error_message(failure)))
          |> Session.append_event(
            Tilde.assistant_turn_error(failure, block_id: state.agent_loop.block_id)
          )
        end)
        |> clear_runtime()
        |> emit_then(emit)
        |> maybe_start_pending(emit)
    end
  end

  @doc false
  @spec shutdown(server_state()) :: :ok
  def shutdown(state) do
    cancel_checkpoint(state.agent_loop.runtime)
    cancel_task(state.agent_loop.task)
    cancel_task_timer(state.agent_loop.timeout_timer)
    :ok
  end

  @spec handle_stream_event(server_state(), Jidoka.Event.t(), emit_fun()) :: server_state()
  def handle_stream_event(state, %Jidoka.Event{event: :turn_started} = event, _emit) do
    state
    |> put_agent_loop(State.put_started_runtime(state.agent_loop, event))
    |> sync_runtime_metadata()
  end

  def handle_stream_event(state, %Jidoka.Event{event: :turn_hibernated} = event, _emit) do
    state
    |> put_agent_loop(State.put_checkpoint(state.agent_loop, event))
    |> sync_runtime_metadata()
  end

  def handle_stream_event(state, %Jidoka.Event{event: :turn_failed} = event, emit) do
    if JidokaEvent.cancelled?(event) do
      state
      |> update_session(
        &Session.append_event(
          &1,
          Tilde.assistant_turn_cancelled(block_id: state.agent_loop.block_id)
        )
      )
      |> clear_runtime()
      |> emit_then(emit)
      |> maybe_start_pending(emit)
    else
      append_runtime_failure(state, event, emit)
    end
  end

  def handle_stream_event(state, %Jidoka.Event{event: :llm_delta} = event, emit) do
    case JidokaEvent.delta(event) do
      {chunk_type, text} -> append_delta(state, text, chunk_type, emit)
      nil -> state
    end
  end

  def handle_stream_event(
        state,
        %Jidoka.Event{event: :effect_started, effect_kind: :operation} = event,
        emit
      ) do
    case JidokaEvent.operation_started(event) do
      %ToolEvent{} = tool_event -> emit_tool_started(state, tool_event, emit)
      nil -> state
    end
  end

  def handle_stream_event(
        state,
        %Jidoka.Event{event: event_name, effect_kind: :operation} = event,
        emit
      )
      when event_name in [:effect_completed, :effect_failed] do
    case JidokaEvent.operation_finished(event) do
      %ToolEvent{} = tool_event ->
        state
        |> update_session(&append_tool_result(&1, tool_event))
        |> emit_then(emit)

      nil ->
        state
    end
  end

  def handle_stream_event(state, %Jidoka.Event{event: :turn_finished} = event, emit) do
    text = JidokaEvent.terminal_text(event)
    metadata = JidokaEvent.terminal_metadata(state.agent_loop.runtime, event)

    state
    |> update_session(fn session ->
      session
      |> maybe_append_done(state.agent_loop.block_id, text, metadata)
      |> Session.append_event(
        Tilde.assistant_turn_finished(
          block_id: state.agent_loop.block_id,
          metadata: metadata
        )
      )
    end)
    |> clear_runtime()
    |> emit_then(emit)
    |> maybe_start_pending(emit)
  end

  def handle_stream_event(state, _event, _emit), do: state

  defp append_runtime_failure(state, %Jidoka.Event{} = event, emit) do
    reason = JidokaEvent.failure_reason(event)

    state
    |> update_session(fn session ->
      session
      |> Session.append_event(Tilde.assistant_done(llm_error_message(reason)))
      |> Session.append_event(
        Tilde.assistant_turn_error(reason, block_id: state.agent_loop.block_id)
      )
    end)
    |> clear_runtime()
    |> emit_then(emit)
    |> maybe_start_pending(emit)
  end

  defp resumable_runtime?(%Session{} = session, %AgentRuntime{} = runtime) do
    AgentRuntime.resumable?(runtime) and not Session.assistant_active?(session)
  end

  defp append_delta(state, text, chunk_type, emit) do
    state
    |> update_session(
      &Session.append_event(
        &1,
        Tilde.assistant_delta(text,
          block_id: state.agent_loop.block_id,
          metadata: %{chunk_type: chunk_type}
        )
      )
    )
    |> emit_then(emit)
  end

  @spec maybe_start_pending(server_state(), emit_fun()) :: server_state()
  def maybe_start_pending(state, emit) do
    case State.pop_queue(state.agent_loop) do
      {%Prompt{} = prompt, agent_loop} ->
        state
        |> put_agent_loop(agent_loop)
        |> maybe_start_rate_limited(prompt, emit)

      {nil, _agent_loop} ->
        state
    end
  end

  defp maybe_start_rate_limited(state, prompt, emit) do
    case RateLimit.check_llm(state.session) do
      :ok ->
        start(state, prompt, emit)

      {:error, {:rate_limited, retry_after}} ->
        state
        |> update_session(
          &Session.append_event(&1, Tilde.assistant_done(rate_limit_message(retry_after)))
        )
        |> emit_then(emit)
    end
  end

  defp enqueue_prompt(state, prompt) do
    put_agent_loop(state, State.enqueue(state.agent_loop, prompt))
  end

  defp start(state, %Prompt{} = prompt, emit) do
    parent = self()
    ref = make_ref()
    block_id = assistant_block_id(state.session)

    state =
      state
      |> update_session(
        &Session.append_event(&1, Tilde.assistant_turn_started(block_id: block_id))
      )
      |> emit_then(emit)

    {:ok, task} = start_task(state, parent, ref, prompt.text)
    timeout_timer = start_task_timer(state, parent, ref, task)

    put_agent_loop(
      state,
      State.start(state.agent_loop, prompt, task, ref, timeout_timer, block_id)
    )
  end

  defp resume(state, %AgentRuntime{} = runtime, emit) do
    parent = self()
    ref = make_ref()
    block_id = runtime.block_id || assistant_block_id(state.session)

    state =
      state
      |> update_session(
        &Session.append_event(&1, Tilde.assistant_turn_started(block_id: block_id))
      )
      |> emit_then(emit)

    runtime = %{runtime | block_id: block_id}
    {:ok, task} = start_resume_task(state, parent, ref, runtime)
    timeout_timer = start_task_timer(state, parent, ref, task)

    state
    |> put_agent_loop(State.resume(state.agent_loop, runtime, task, ref, timeout_timer, block_id))
    |> sync_runtime_metadata()
  end

  defp start_task(%{session: %Session{}} = state, parent, ref, prompt) when is_pid(parent) do
    Task.Supervisor.start_child(Tilde.Session.TaskSupervisor, fn ->
      Process.link(parent)
      stream_to_parent(state, parent, ref, prompt)
    end)
  end

  defp start_resume_task(%{session: %Session{}} = state, parent, ref, %AgentRuntime{} = runtime)
       when is_pid(parent) do
    Task.Supervisor.start_child(Tilde.Session.TaskSupervisor, fn ->
      Process.link(parent)
      resume_to_parent(state, parent, ref, runtime)
    end)
  end

  defp start_task_timer(%{agent_task_timeout_ms: :infinity}, _parent, _ref, _task), do: nil

  defp start_task_timer(%{agent_task_timeout_ms: timeout}, parent, ref, task)
       when is_integer(timeout) and timeout > 0 do
    Process.send_after(parent, {:tilde_agent_timeout, ref, task}, timeout)
  end

  defp stream_to_parent(%{session: %Session{} = session} = state, parent, ref, prompt) do
    deliver_stream(parent, ref, fn ->
      LLM.stream(session, [prompt: prompt] ++ llm_opts(state))
    end)
  end

  defp resume_to_parent(
         %{session: %Session{} = session} = state,
         parent,
         ref,
         %AgentRuntime{} = runtime
       ) do
    deliver_stream(parent, ref, fn ->
      LLM.resume_checkpoint(session, runtime, llm_opts(state))
    end)
  end

  defp llm_opts(%{session: %Session{metadata: metadata}} = state) do
    state
    |> Map.get(:llm_opts, [])
    |> Keyword.merge(session_llm_opts(metadata))
  end

  defp session_llm_opts(metadata) do
    case Map.get(metadata, :app_referer) do
      referer when is_binary(referer) and referer != "" -> [app_referer: referer]
      _other -> []
    end
  end

  defp deliver_stream(parent, ref, fun) when is_function(fun, 0) do
    fun.()
    |> Enum.each(&send(parent, {:tilde_agent_stream, ref, &1}))
  rescue
    exception in [
      RuntimeError,
      ArgumentError,
      ArithmeticError,
      MatchError,
      FunctionClauseError,
      CaseClauseError,
      CondClauseError,
      WithClauseError,
      KeyError,
      BadMapError,
      Protocol.UndefinedError,
      UndefinedFunctionError
    ] ->
      send(parent, {:tilde_agent_stream, ref, failed_event({:exception, :error, exception})})
  catch
    kind, reason ->
      send(parent, {:tilde_agent_stream, ref, failed_event({:exception, kind, reason})})
  end

  defp failed_event(reason) do
    LLM.failed_event(reason, source: "tilde-agent-loop")
  end

  defp cancel_checkpoint(%AgentRuntime{checkpoint_token: token}) when is_binary(token) do
    _result = LLM.cancel_checkpoint(token)
    :ok
  end

  defp cancel_checkpoint(_run), do: :ok

  defp cancel_task(nil), do: :ok

  defp cancel_task(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp clear_runtime(state) do
    cancel_task_timer(state.agent_loop.timeout_timer)

    state
    |> put_agent_loop(State.clear_active(state.agent_loop))
    |> sync_runtime_metadata()
  end

  defp cancel_task_timer(timer) when is_reference(timer) do
    Process.cancel_timer(timer, async: false, info: false)
    :ok
  end

  defp cancel_task_timer(nil), do: :ok

  defp emit_tool_started(state, %ToolEvent{} = event, emit) do
    state
    |> update_session(fn session ->
      Session.append_event(
        session,
        Tilde.tool_started(to_string(event.name || "tool"), event.args || %{},
          tool_call_id: event.id,
          metadata: tool_metadata(event)
        )
      )
    end)
    |> emit_then(emit)
  end

  defp append_tool_result(%Session{} = session, %ToolEvent{} = event) do
    Session.append_event(
      session,
      Tilde.tool_done(event.id, event.status || :success, event.output,
        metadata: tool_metadata(event)
      )
    )
  end

  defp put_agent_loop(state, %State{} = agent_loop), do: %{state | agent_loop: agent_loop}

  defp sync_runtime_metadata(state) do
    update_session(state, &Session.put_agent_runtime(&1, State.runtime(state.agent_loop)))
  end

  defp update_session(state, fun) when is_function(fun, 1) do
    %{state | session: fun.(state.session)}
  end

  defp emit_then(state, emit) do
    emit.(state)
    state
  end

  defp maybe_append_done(%Session{} = session, block_id, text, metadata) when is_binary(text) do
    cond do
      String.trim(text) == "" ->
        session

      max_iterations_terminal?(text, metadata) ->
        session

      true ->
        append_terminal_text(session, block_id, text, metadata)
    end
  end

  defp max_iterations_terminal?(_text, metadata) when is_map(metadata) do
    Map.get(metadata, :termination_reason) == :max_iterations
  end

  defp append_terminal_text(%Session{} = session, block_id, text, metadata) do
    case assistant_block_source(session, block_id) do
      nil ->
        Session.append_event(
          session,
          Tilde.assistant_done(text, block_id: block_id, metadata: metadata)
        )

      source ->
        if terminal_text_present?(source, text) do
          session
        else
          Session.append_event(
            session,
            Tilde.assistant_delta(terminal_text_delta(source, text),
              block_id: block_id,
              metadata: Map.put(metadata, :chunk_type, :content)
            )
          )
        end
    end
  end

  defp tool_metadata(%ToolEvent{} = event) do
    %{}
    |> Map.put(:tool_call_id, event.id)
    |> Map.put(:tool_name, event.name)
    |> reject_nil_values()
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp assistant_block_source(%Session{} = session, block_id) do
    session.transcript.blocks
    |> Enum.reverse()
    |> Enum.find(&assistant_block_segment?(&1, block_id))
    |> case do
      %{source: source} when is_binary(source) -> source
      _block -> nil
    end
  end

  defp assistant_block_segment?(%{id: id, role: :assistant}, block_id) when id == block_id,
    do: true

  defp assistant_block_segment?(%{role: :assistant, metadata: metadata}, block_id)
       when is_map(metadata) do
    Map.get(metadata, :root_block_id) == block_id
  end

  defp assistant_block_segment?(_block, _block_id), do: false

  defp terminal_text_present?(source, text) do
    String.trim(source) == String.trim(text) or String.contains?(source, text)
  end

  defp terminal_text_delta("", text), do: text

  defp terminal_text_delta(source, text) do
    if String.ends_with?(source, ["\n", " "]), do: text, else: "\n\n#{text}"
  end

  defp assistant_block_id(%Session{} = session) do
    "msg_assistant_#{session.event_count + 1}"
  end

  defp new_input_submitted?(%Session{} = previous, %Session{} = session) do
    case Session.latest_event(session) do
      %Event{type: :input_submitted, id: id} -> not event_id?(previous, id)
      _event -> false
    end
  end

  defp event_id?(%Session{} = session, id) do
    Session.event_id?(session, id)
  end

  defp latest_input_submission(%Session{} = session) do
    session
    |> Session.events()
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.find(fn {%Event{type: type}, _index} -> type == :input_submitted end)
    |> case do
      {%Event{} = event, index} -> {index, event}
      nil -> nil
    end
  end

  defp rate_limit_message(retry_after) do
    seconds = retry_after |> div(1_000) |> max(1)
    "The public demo is busy. Please try again in #{seconds}s."
  end

  defp llm_error_message(:missing_openrouter_api_key),
    do: "The model is not configured yet. Set OPENROUTER_API_KEY to enable assistant replies."

  defp llm_error_message(_reason), do: "The model is unavailable right now. Please try again."
end
