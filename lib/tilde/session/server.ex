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
  alias Tilde.Session.PromptLifecycle

  defstruct session: nil,
            subscribers: %{},
            responding?: false,
            responding_to_input_index: nil,
            prompt_task: nil,
            prompt_ref: nil,
            prompt_block_id: nil

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
      nil -> start_link(Keyword.put(opts, :name, name))
      pid -> {:ok, pid}
    end
  end

  @doc "Returns the current session."
  @spec get_session(name()) :: Session.t()
  def get_session(server \\ __MODULE__), do: GenServer.call(server, :get_session)

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

  @impl true
  def init(%Session{} = session), do: {:ok, %__MODULE__{session: session}}

  @impl true
  def handle_call(:get_session, _from, state), do: {:reply, state.session, state}

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
    state = %{state | session: state.session |> fun.() |> trim_session()}
    state = handle_post_update(previous, state)
    {:reply, state.session, state}
  end

  def handle_call({:apply_key, key}, _from, state) do
    case Controller.apply_key(state.session, key) do
      {:cont, session} ->
        previous = state.session
        state = %{state | session: trim_session(session)}
        state = handle_post_update(previous, state)
        {:reply, {:cont, state.session}, state}

      {:halt, session} ->
        previous = state.session
        state = %{state | session: trim_session(session)}
        state = handle_post_update(previous, state)
        {:reply, {:halt, state.session}, state}
    end
  end

  @impl true
  def handle_info({:tilde_prompt_stream, ref, event}, %{prompt_ref: ref} = state) do
    state = PromptLifecycle.handle_stream_event(state, event, &broadcast/1)
    {:noreply, state}
  end

  def handle_info({:tilde_prompt_stream, _stale_ref, _event}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, update_in(state.subscribers, &Map.delete(&1, ref))}
  end

  defp handle_post_update(previous, %__MODULE__{} = state) do
    case maybe_apply_command(state) do
      {:command, state} ->
        broadcast(state)
        state

      :not_command ->
        broadcast(state)
        PromptLifecycle.maybe_start(state, previous, &broadcast/1)
    end
  end

  defp maybe_apply_command(%__MODULE__{} = state) do
    with %Event{type: :input_submitted, text: text} <- List.last(state.session.events),
         {:ok, command} <- Command.parse(text) do
      effects = Command.run(command, state.session, [])

      {:command,
       %{state | session: state.session |> Command.apply_effects(effects) |> trim_session()}}
    else
      _other -> :not_command
    end
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
