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

  defstruct session: nil,
            subscribers: %{},
            agent_loop: AgentLoopState.new()

  @type t :: %__MODULE__{
          session: Session.t(),
          subscribers: %{reference() => pid()},
          agent_loop: AgentLoopState.t()
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
    if AgentLoopState.matches_ref?(state.agent_loop, ref) do
      previous = state.session
      state = AgentLoop.handle_stream_event(state, event, &broadcast/1)
      Persistence.persist(previous, state.session)
      {:noreply, state}
    else
      {:noreply, state}
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

      {:command,
       %{state | session: state.session |> Command.apply_effects(effects) |> trim_session()}}
    else
      _other -> :not_command
    end
  end

  defp put_session(%__MODULE__{} = state, %Session{} = session) do
    %{state | session: trim_session(session)}
  end

  defp trim_session(%Session{} = session) do
    Session.trim_events(session, Application.get_env(:tilde, :session_event_limit, false))
  end

  defp broadcast(%__MODULE__{} = state) do
    message = {:tilde_session_updated, state.session.id, state.session}
    Enum.each(state.subscribers, fn {_ref, pid} -> send(pid, message) end)
  end

  defp pop_subscriber_refs(subscribers, pid) do
    {matching, remaining} = Enum.split_with(subscribers, fn {_ref, sub_pid} -> sub_pid == pid end)
    {Enum.map(matching, &elem(&1, 0)), Map.new(remaining)}
  end
end
