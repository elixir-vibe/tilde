defmodule Tilde.Session.AgentLoop do
  @moduledoc "Session-owned assistant loop: start, stream, cancel, and record semantic events."

  alias Tilde.Core.{AgentRuntime, Event, Session}
  alias Tilde.Runtime.{LLM, RateLimit}
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

  def handle_stream_event(state, %Jidoka.Event{event: :turn_failed, data: data}, emit)
      when data in [
             %{reason: :cancelled},
             %{"reason" => "cancelled"},
             %{error: :cancelled},
             %{"error" => "cancelled"}
           ] do
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
  end

  def handle_stream_event(state, %Jidoka.Event{event: :llm_delta, data: data}, emit) do
    chunk_type = event_field(data, :chunk_type, :content)
    text = event_field(data, :delta, "")

    cond do
      chunk_type in [:content, "content"] and is_binary(text) and text != "" ->
        append_delta(state, text, :content, emit)

      chunk_type in [:thinking, "thinking"] and is_binary(text) and text != "" ->
        append_delta(state, text, :thinking, emit)

      true ->
        state
    end
  end

  def handle_stream_event(
        state,
        %Jidoka.Event{event: :effect_started, effect_kind: :operation, data: data} = event,
        emit
      ) do
    if operation_arguments?(data) do
      id = event.effect_id || event_field(data, :tool_call_id)
      name = event.operation || event_field(data, :tool_name, "tool")
      args = event_field(data, :arguments, %{})
      tool_event = ToolEvent.started(id: id, name: name, args: args)
      emit_tool_started(state, tool_event, emit)
    else
      state
    end
  end

  def handle_stream_event(
        state,
        %Jidoka.Event{event: event_name, effect_kind: :operation, data: data} = event,
        emit
      )
      when event_name in [:effect_completed, :effect_failed] do
    case operation_result(data) do
      nil ->
        state

      raw_result ->
        id = event.effect_id || event_field(data, :tool_call_id)

        tool_event =
          ToolEvent.finished(
            id: id,
            status: tool_status(raw_result),
            output: tool_result(raw_result)
          )

        state
        |> update_session(&append_tool_result(&1, tool_event))
        |> emit_then(emit)
    end
  end

  def handle_stream_event(state, %Jidoka.Event{event: :turn_finished, data: data}, emit) do
    text = data |> event_field(:result, "") |> to_string()

    state
    |> update_session(fn session ->
      session
      |> maybe_append_done(state.agent_loop.block_id, text, runtime_metadata(state, data))
      |> Session.append_event(
        Tilde.assistant_turn_finished(
          block_id: state.agent_loop.block_id,
          metadata: runtime_metadata(state, data)
        )
      )
    end)
    |> clear_runtime()
    |> emit_then(emit)
    |> maybe_start_pending(emit)
  end

  def handle_stream_event(state, %Jidoka.Event{event: :turn_failed, data: data}, emit) do
    reason = event_field(data, :error, data)

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

  def handle_stream_event(state, _event, _emit), do: state

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

  defp event_field(data, key, default \\ nil) when is_atom(key) do
    Map.get(data, key, Map.get(data, Atom.to_string(key), default))
  end

  defp operation_arguments?(data) when is_map(data), do: event_field(data, :arguments) != nil
  defp operation_arguments?(_data), do: false

  defp operation_result(data) when is_map(data) do
    event_field(data, :result) || event_field(data, :error) || event_field(data, :output)
  end

  defp operation_result(_data), do: nil

  defp tool_status({:ok, _result, _meta}), do: :success
  defp tool_status({:ok, _result}), do: :success
  defp tool_status(_other), do: :error

  defp tool_result({:ok, result, _meta}), do: result
  defp tool_result({:ok, result}), do: result
  defp tool_result(result), do: result

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

    put_agent_loop(state, State.start(state.agent_loop, prompt, task, ref, block_id))
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

    state
    |> put_agent_loop(State.resume(state.agent_loop, runtime, task, ref, block_id))
    |> sync_runtime_metadata()
  end

  defp start_task(%{session: %Session{}} = state, parent, ref, prompt) when is_pid(parent) do
    Task.start(fn -> stream_to_parent(state, parent, ref, prompt) end)
  end

  defp start_resume_task(%{session: %Session{}} = state, parent, ref, %AgentRuntime{} = runtime)
       when is_pid(parent) do
    Task.start(fn -> resume_to_parent(state, parent, ref, runtime) end)
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
    state
    |> put_agent_loop(State.clear_active(state.agent_loop))
    |> sync_runtime_metadata()
  end

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

  defp runtime_metadata(state, event_data) do
    state.agent_loop.runtime
    |> runtime_snapshot()
    |> Map.merge(
      reject_nil_values(%{
        usage: event_field(event_data, :usage),
        termination_reason: event_field(event_data, :termination_reason),
        thinking_content: event_field(event_data, :thinking_content),
        reasoning_details: event_field(event_data, :reasoning_details),
        jidoka: event_field(event_data, :jidoka)
      })
    )
    |> reject_nil_values()
    |> sanitize_runtime_metadata()
  end

  defp runtime_snapshot(nil), do: %{}

  defp runtime_snapshot(%AgentRuntime{} = runtime) do
    runtime
    |> AgentRuntime.dump()
    |> Map.take([:run_id, :request_id, :checkpoint_token, :iteration])
    |> reject_nil_values()
  end

  defp sanitize_runtime_metadata(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case sanitize_runtime_value(value) do
        nil -> acc
        sanitized -> Map.put(acc, key, sanitized)
      end
    end)
  end

  defp sanitize_runtime_value(value)
       when is_pid(value) or is_reference(value) or is_function(value), do: nil

  defp sanitize_runtime_value(value)
       when is_binary(value) or is_number(value) or is_boolean(value), do: value

  defp sanitize_runtime_value(value) when is_atom(value), do: value

  defp sanitize_runtime_value(value) when is_list(value) do
    value
    |> Enum.map(&sanitize_runtime_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp sanitize_runtime_value(value) when is_map(value), do: sanitize_runtime_metadata(value)

  defp sanitize_runtime_value(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> sanitize_runtime_value()
  end

  defp sanitize_runtime_value(value), do: inspect(value)

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
    "msg_assistant_#{length(session.events) + 1}"
  end

  defp new_input_submitted?(%Session{} = previous, %Session{} = session) do
    case List.last(session.events) do
      %Event{type: :input_submitted, id: id} -> not event_id?(previous, id)
      _event -> false
    end
  end

  defp event_id?(%Session{} = session, id) do
    Enum.any?(session.events, &(&1.id == id))
  end

  defp latest_input_submission(%Session{} = session) do
    session.events
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
