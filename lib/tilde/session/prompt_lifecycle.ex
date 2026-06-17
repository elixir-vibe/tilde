defmodule Tilde.Session.PromptLifecycle do
  @moduledoc "Prompt submission, streaming, tool projection, and result recording."

  alias Tilde.Command
  alias Tilde.Core.{Event, Session}
  alias Tilde.Runtime.{LLM, RateLimit}
  alias Tilde.Session.PromptRunner
  alias Tilde.Tool.Event, as: ToolEvent

  @type server_state :: map()
  @type emit_fun :: (server_state() -> term())

  @spec maybe_start(server_state(), Session.t(), emit_fun()) :: server_state()
  def maybe_start(%{responding?: true} = state, _previous, _emit), do: state

  def maybe_start(%{session: %Session{} = session} = state, %Session{} = previous, emit) do
    if LLM.enabled?() and new_input_submitted?(previous, session) do
      maybe_start_rate_limited(state, emit)
    else
      state
    end
  end

  @spec handle_stream_event(server_state(), Tilde.Runtime.LLM.Provider.stream_event(), emit_fun()) ::
          server_state()
  def handle_stream_event(state, {:delta, text}, emit) do
    state
    |> update_session(
      &Session.append_event(&1, Tilde.assistant_delta(text, block_id: state.prompt_block_id))
    )
    |> emit_then(emit)
  end

  def handle_stream_event(state, {:tool_preparing, tool_call_id, name, args}, emit) do
    tool_event = ToolEvent.preparing(id: tool_call_id, name: name, args: args)
    emit_tool_started(state, tool_event, emit)
  end

  def handle_stream_event(state, {:tool_started, tool_call_id, name, args}, emit) do
    tool_event = ToolEvent.started(id: tool_call_id, name: name, args: args)
    emit_tool_started(state, tool_event, emit)
  end

  def handle_stream_event(state, {:tool_done, tool_call_id, status, result}, emit) do
    tool_event = ToolEvent.finished(id: tool_call_id, status: status, output: result)

    state
    |> update_session(&append_tool_result(&1, tool_event))
    |> emit_then(emit)
  end

  def handle_stream_event(state, {:done, text}, emit) do
    answered_input_index = state.responding_to_input_index

    state =
      state
      |> update_session(fn session ->
        session
        |> Session.append_event(Tilde.status_changed("model", nil))
        |> maybe_append_done(state.prompt_block_id, text)
      end)
      |> Map.merge(%{
        responding?: false,
        responding_to_input_index: nil,
        prompt_task: nil,
        prompt_ref: nil,
        prompt_block_id: nil
      })
      |> emit_then(emit)

    maybe_start_pending(state, answered_input_index, emit)
  end

  def handle_stream_event(state, {:error, reason}, emit) do
    answered_input_index = state.responding_to_input_index

    state =
      state
      |> update_session(fn session ->
        session
        |> Session.append_event(Tilde.status_changed("model", nil))
        |> Session.append_event(Tilde.assistant_done(llm_error_message(reason)))
      end)
      |> Map.merge(%{
        responding?: false,
        responding_to_input_index: nil,
        prompt_task: nil,
        prompt_ref: nil,
        prompt_block_id: nil
      })
      |> emit_then(emit)

    maybe_start_pending(state, answered_input_index, emit)
  end

  def handle_stream_event(state, _event, _emit), do: state

  @spec maybe_start_pending(server_state(), non_neg_integer() | nil, emit_fun()) :: server_state()
  def maybe_start_pending(state, nil, _emit), do: state

  def maybe_start_pending(%{session: %Session{} = session} = state, answered_input_index, emit) do
    with true <- LLM.enabled?(),
         {latest_index, %Event{text: text}} when latest_index > answered_input_index <-
           latest_input_submission(session),
         :error <- Command.parse(text) do
      maybe_start_rate_limited(state, emit)
    else
      _other -> state
    end
  end

  defp maybe_start_rate_limited(state, emit) do
    case RateLimit.check_llm(state.session) do
      :ok ->
        start(state, emit)

      {:error, {:rate_limited, retry_after}} ->
        state
        |> update_session(
          &Session.append_event(&1, Tilde.assistant_done(rate_limit_message(retry_after)))
        )
        |> emit_then(emit)
    end
  end

  defp start(state, emit) do
    parent = self()
    ref = make_ref()
    block_id = assistant_block_id(state.session)

    state =
      state
      |> update_session(&Session.append_event(&1, Tilde.status_changed("model", "thinking…")))
      |> emit_then(emit)

    {:ok, task} = PromptRunner.start(state.session, parent, ref)

    %{
      state
      | responding?: true,
        responding_to_input_index: latest_input_index(state.session),
        prompt_task: task,
        prompt_ref: ref,
        prompt_block_id: block_id
    }
  end

  defp emit_tool_started(state, %ToolEvent{} = event, emit) do
    state
    |> update_session(
      &Session.append_event(
        &1,
        Tilde.tool_started(to_string(event.name || "tool"), event.args || %{},
          tool_call_id: event.id
        )
      )
    )
    |> emit_then(emit)
  end

  defp append_tool_result(%Session{} = session, %ToolEvent{} = event) do
    session
    |> Session.append_event(
      Tilde.tool_stream(event.id, :result, inspect(event.output, pretty: true, limit: 20))
    )
    |> Session.append_event(Tilde.tool_done(event.id, event.status || :success, event.output))
  end

  defp update_session(state, fun) when is_function(fun, 1) do
    %{state | session: state.session |> fun.() |> trim_session()}
  end

  defp emit_then(state, emit) do
    emit.(state)
    state
  end

  defp maybe_append_done(%Session{} = session, block_id, text) when is_binary(text) do
    if assistant_block?(session, block_id) or String.trim(text) == "" do
      session
    else
      Session.append_event(session, Tilde.assistant_done(text, block_id: block_id))
    end
  end

  defp assistant_block?(%Session{} = session, block_id) do
    Enum.any?(session.transcript.blocks, &(&1.id == block_id and &1.role == :assistant))
  end

  defp assistant_block_id(%Session{} = session) do
    "msg_assistant_#{length(session.events) + 1}"
  end

  defp new_input_submitted?(%Session{} = previous, %Session{} = session) do
    length(session.events) > length(previous.events) and
      last_event_type(session) == :input_submitted
  end

  defp latest_input_index(%Session{} = session) do
    case latest_input_submission(session) do
      {index, %Event{}} -> index
      nil -> nil
    end
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

  defp last_event_type(%Session{events: [%Event{} | _] = events}),
    do: events |> List.last() |> Map.get(:type)

  defp last_event_type(_session), do: nil

  defp trim_session(%Session{} = session) do
    Session.trim_events(session, Application.get_env(:tilde, :session_event_limit, false))
  end

  defp rate_limit_message(retry_after) do
    seconds = retry_after |> div(1_000) |> max(1)
    "The public demo is busy. Please try again in #{seconds}s."
  end

  defp llm_error_message(:missing_openrouter_api_key),
    do: "The model is not configured yet. Set OPENROUTER_API_KEY to enable assistant replies."

  defp llm_error_message(_reason), do: "The model is unavailable right now. Please try again."
end
