defmodule Tilde.Session.Server do
  @moduledoc """
  Process owner for a semantic Tilde session.

  The server keeps one `%Tilde.Core.Session{}` and broadcasts updates to subscribers.
  Renderers such as LiveView and SSH can subscribe to the same server to mirror a
  single semantic session without sharing DOM, ANSI, or terminal state.
  """

  use GenServer

  alias Tilde.Command
  alias Tilde.Core.{Controller, Event, Session}
  alias Tilde.Session.AgentLoop
  alias Tilde.Session.AgentLoop.ResumeCandidate
  alias Tilde.Session.AgentLoop.State, as: AgentLoopState
  alias Tilde.Session.Persistence

  @stream_flush_interval 33

  defstruct session: nil,
            subscribers: %{},
            agent_loop: AgentLoopState.new(),
            stream_buffers: %{}

  @type t :: %__MODULE__{
          session: Session.t(),
          subscribers: %{reference() => pid()},
          agent_loop: AgentLoopState.t(),
          stream_buffers: map()
        }

  @type name :: GenServer.name() | pid()
  @type update_message :: {:tilde_session_updated, String.t(), Session.t()}

  @doc "Starts a session server."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    session = Keyword.get_lazy(opts, :session, &Tilde.session/0)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, session, name: name)
  end

  @doc "Ensures a named server exists and returns `{:ok, pid}`."
  @spec ensure_started(name(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(name \\ __MODULE__, opts \\ []) do
    case GenServer.whereis(name) do
      nil -> start_unlinked(Keyword.put(opts, :name, name))
      pid -> {:ok, pid}
    end
  end

  defp start_unlinked(opts) do
    case start_link(opts) do
      {:ok, pid} ->
        Process.unlink(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns the current session."
  @spec get_session(name()) :: Session.t()
  def get_session(server \\ __MODULE__), do: GenServer.call(server, :get_session)

  @doc "Returns a read-only diagnostics snapshot of the session server."
  @spec dev_snapshot(name()) :: map()
  def dev_snapshot(server \\ __MODULE__), do: GenServer.call(server, :dev_snapshot)

  @doc "Subscribes the caller to session updates and returns the current session."
  @spec subscribe(name()) :: Session.t()
  def subscribe(server \\ __MODULE__), do: GenServer.call(server, {:subscribe, self()})

  @doc "Unsubscribes the caller from session updates."
  @spec unsubscribe(name()) :: :ok
  def unsubscribe(server \\ __MODULE__), do: GenServer.call(server, {:unsubscribe, self()})

  @doc "Appends an event to the default session server and broadcasts the resulting state."
  @spec append_event(Tilde.Core.Event.t()) :: Session.t()
  def append_event(event), do: append_event(__MODULE__, event)

  @doc "Appends an event to the session and broadcasts the resulting state."
  @spec append_event(name(), Tilde.Core.Event.t()) :: Session.t()
  def append_event(server, event) do
    update_session(server, &Session.append_event(&1, event))
  end

  @doc "Updates the default session server and broadcasts the resulting state."
  @spec update_session((Session.t() -> Session.t())) :: Session.t()
  def update_session(fun), do: update_session(__MODULE__, fun)

  @doc "Updates the session and broadcasts the resulting state."
  @spec update_session(name(), (Session.t() -> Session.t())) :: Session.t()
  def update_session(server, fun) when is_function(fun, 1) do
    GenServer.call(server, {:update_session, fun})
  end

  @doc "Applies a decoded TUI key through `Tilde.Core.Controller` on the default server."
  @spec apply_key(Tilde.Core.Keys.key()) :: Controller.result()
  def apply_key(key), do: apply_key(__MODULE__, key)

  @doc "Applies a decoded TUI key through `Tilde.Core.Controller`."
  @spec apply_key(name(), Tilde.Core.Keys.key()) :: Controller.result()
  def apply_key(server, key) do
    GenServer.call(server, {:apply_key, key})
  end

  @doc "Applies a transport-neutral interaction through `Tilde.Core.Controller`."
  @spec apply_interaction(name(), Tilde.Core.Interaction.t()) :: Controller.interaction_result()
  def apply_interaction(server, interaction) do
    GenServer.call(server, {:apply_interaction, interaction})
  end

  @impl true
  def init(%Session{} = session) do
    state =
      %__MODULE__{session: session}
      |> AgentLoop.maybe_resume(&broadcast/1)

    Persistence.persist_if_changed(session, state.session)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_session, _from, state), do: {:reply, state.session, state}

  def handle_call(:dev_snapshot, _from, state) do
    snapshot = %{
      session: state.session,
      agent_loop: AgentLoopState.snapshot(state.agent_loop),
      resume_candidate: ResumeCandidate.from_session(state.session)
    }

    {:reply, snapshot, state}
  end

  def handle_call({:subscribe, pid}, _from, state) when is_pid(pid) do
    ref = Process.monitor(pid)
    state = put_in(state.subscribers[ref], pid)
    {:reply, state.session, state}
  end

  def handle_call({:unsubscribe, pid}, _from, state) when is_pid(pid) do
    {refs, subscribers} = pop_subscriber_refs(state.subscribers, pid)
    Enum.each(refs, &Process.demonitor(&1, [:flush]))
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call({:update_session, fun}, _from, state) do
    previous = state.session
    state = state |> put_session(fun.(state.session)) |> after_session_update(previous)
    {:reply, state.session, state}
  end

  def handle_call({:apply_key, key}, _from, state) do
    case Controller.apply_key(state.session, key) do
      {:cont, session} ->
        previous = state.session
        state = state |> put_session(session) |> after_session_update(previous)
        {:reply, {:cont, state.session}, state}

      {:halt, session} ->
        previous = state.session
        state = state |> put_session(session) |> after_session_update(previous)
        {:reply, {:halt, state.session}, state}
    end
  end

  def handle_call(
        {:apply_interaction, %{type: :interrupt}},
        _from,
        %{agent_loop: %AgentLoopState{active?: true}} = state
      ) do
    previous = state.session
    state = AgentLoop.cancel(state, &broadcast/1)
    Persistence.persist(previous, state.session)
    {:reply, {:cont, state.session, []}, state}
  end

  def handle_call({:apply_interaction, interaction}, _from, state) do
    case Controller.apply_interaction(state.session, interaction) do
      {:cont, session, outcomes} ->
        previous = state.session
        state = state |> put_session(session) |> after_session_update(previous)
        {:reply, {:cont, state.session, outcomes}, state}

      {:halt, session, outcomes} ->
        previous = state.session
        state = state |> put_session(session) |> after_session_update(previous)
        {:reply, {:halt, state.session, outcomes}, state}
    end
  end

  @impl true
  def handle_info({:tilde_agent_stream, ref, event}, state) do
    cond do
      not AgentLoopState.matches_ref?(state.agent_loop, ref) ->
        {:noreply, discard_stream_buffer(state, ref)}

      llm_delta?(event) ->
        {:noreply, buffer_stream_delta(state, ref, event)}

      true ->
        previous = state.session

        state =
          state
          |> flush_stream_buffer(ref)
          |> AgentLoop.handle_stream_event(event, &broadcast/1)

        Persistence.persist(previous, state.session)
        {:noreply, state}
    end
  end

  def handle_info({:tilde_stream_flush, ref}, state) do
    if AgentLoopState.matches_ref?(state.agent_loop, ref) do
      {:noreply, flush_stream_buffer(state, ref)}
    else
      {:noreply, discard_stream_buffer(state, ref)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, update_in(state.subscribers, &Map.delete(&1, ref))}
  end

  defp after_session_update(%__MODULE__{} = state, %Session{} = previous) do
    state =
      case apply_command_if_submitted(state) do
        {:command, state} ->
          broadcast(state)
          state

        :not_command ->
          broadcast(state)
          AgentLoop.maybe_start(state, previous, &broadcast/1)
      end

    Persistence.persist(previous, state.session)
    state
  end

  defp apply_command_if_submitted(%__MODULE__{} = state) do
    with %Event{type: :input_submitted, text: text} <- List.last(state.session.events),
         {:ok, command} <- Command.parse(text) do
      effects = Command.run(command, state.session, [])

      {:command, %{state | session: Command.apply_effects(state.session, effects)}}
    else
      _other -> :not_command
    end
  end

  defp put_session(%__MODULE__{} = state, %Session{} = session) do
    %{state | session: session}
  end

  defp llm_delta?(%{kind: :llm_delta} = event) do
    event
    |> delta_text()
    |> case do
      text when is_binary(text) -> text != ""
      _other -> false
    end
  end

  defp llm_delta?(_event), do: false

  defp buffer_stream_delta(%__MODULE__{stream_buffers: buffers} = state, ref, event) do
    buffer = Map.get_lazy(buffers, ref, fn -> new_stream_buffer(ref) end)
    buffer = %{buffer | events: [event | buffer.events]}
    %{state | stream_buffers: Map.put(buffers, ref, buffer)}
  end

  defp new_stream_buffer(ref) do
    %{
      events: [],
      timer: Process.send_after(self(), {:tilde_stream_flush, ref}, @stream_flush_interval)
    }
  end

  defp flush_stream_buffer(%__MODULE__{} = state, ref) do
    case Map.pop(state.stream_buffers, ref) do
      {nil, _buffers} -> state
      {buffer, buffers} -> flush_stream_buffer(state, buffer, buffers)
    end
  end

  defp flush_stream_buffer(%__MODULE__{} = state, %{events: events, timer: timer}, buffers) do
    cancel_stream_timer(timer)
    previous = state.session

    state =
      events
      |> Enum.reverse()
      |> coalesced_delta_events()
      |> Enum.reduce(%{state | stream_buffers: buffers}, &apply_buffered_delta/2)

    Persistence.persist(previous, state.session)
    broadcast(state)
    state
  end

  defp apply_buffered_delta(event, state) do
    AgentLoop.handle_stream_event(state, event, fn _state -> :ok end)
  end

  defp discard_stream_buffer(%__MODULE__{} = state, ref) do
    case Map.pop(state.stream_buffers, ref) do
      {nil, _buffers} ->
        state

      {%{timer: timer}, buffers} ->
        cancel_stream_timer(timer)
        %{state | stream_buffers: buffers}
    end
  end

  defp cancel_stream_timer(timer) when is_reference(timer) do
    Process.cancel_timer(timer, async: false, info: false)
  end

  defp coalesced_delta_events(events) do
    events
    |> Enum.chunk_while([], &chunk_delta_event/2, &after_delta_chunk/1)
    |> Enum.map(&combine_delta_events/1)
  end

  defp chunk_delta_event(event, []) do
    {:cont, [event]}
  end

  defp chunk_delta_event(event, [%{kind: :llm_delta} = previous | _rest] = chunk) do
    if delta_chunk_type(event) == delta_chunk_type(previous) do
      {:cont, [event | chunk]}
    else
      {:cont, Enum.reverse(chunk), [event]}
    end
  end

  defp after_delta_chunk([]), do: {:cont, []}
  defp after_delta_chunk(chunk), do: {:cont, Enum.reverse(chunk), []}

  defp combine_delta_events([event]), do: event

  defp combine_delta_events([first | _rest] = events) do
    text = Enum.map_join(events, &delta_text/1)
    chunk_type = delta_chunk_type(first)

    data =
      first.data
      |> Map.put(:delta, text)
      |> Map.put(:chunk_type, chunk_type)

    %{first | data: data}
  end

  defp delta_text(%{data: data}) when is_map(data),
    do: Map.get(data, :delta, Map.get(data, "delta", ""))

  defp delta_chunk_type(%{data: data}) when is_map(data),
    do: Map.get(data, :chunk_type, Map.get(data, "chunk_type", :content))

  defp broadcast(%__MODULE__{} = state) do
    message = {:tilde_session_updated, state.session.id, state.session}
    Enum.each(state.subscribers, fn {_ref, pid} -> send(pid, message) end)
  end

  defp pop_subscriber_refs(subscribers, pid) do
    {matching, remaining} = Enum.split_with(subscribers, fn {_ref, sub_pid} -> sub_pid == pid end)
    {Enum.map(matching, &elem(&1, 0)), Map.new(remaining)}
  end
end
