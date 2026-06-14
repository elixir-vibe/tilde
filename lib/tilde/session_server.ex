defmodule Tilde.SessionServer do
  @moduledoc """
  Process owner for a semantic Tilde session.

  The server keeps one `%Tilde.Session{}` and broadcasts updates to subscribers.
  Renderers such as LiveView and SSH can subscribe to the same server to mirror a
  single semantic session without sharing DOM, ANSI, or terminal state.
  """

  use GenServer

  alias Tilde.{Event, LLM, Session}
  alias Tilde.TUI.Controller

  defstruct session: nil, subscribers: %{}, responding?: false

  @type name :: GenServer.name()
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
  @spec append_event(Tilde.Event.t()) :: Session.t()
  def append_event(event), do: append_event(__MODULE__, event)

  @doc "Appends an event to the session and broadcasts the resulting state."
  @spec append_event(name(), Tilde.Event.t()) :: Session.t()
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

  @doc "Applies a decoded TUI key through `Tilde.TUI.Controller` on the default server."
  @spec apply_key(Tilde.TUI.Keys.key()) :: Controller.result()
  def apply_key(key), do: apply_key(__MODULE__, key)

  @doc "Applies a decoded TUI key through `Tilde.TUI.Controller`."
  @spec apply_key(name(), Tilde.TUI.Keys.key()) :: Controller.result()
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
    state = %{state | session: fun.(state.session)}
    broadcast(state)
    state = maybe_start_llm_response(previous, state)
    {:reply, state.session, state}
  end

  def handle_call({:apply_key, key}, _from, state) do
    case Controller.apply_key(state.session, key) do
      {:cont, session} ->
        previous = state.session
        state = %{state | session: session}
        broadcast(state)
        state = maybe_start_llm_response(previous, state)
        {:reply, {:cont, session}, state}

      {:halt, session} ->
        previous = state.session
        state = %{state | session: session}
        broadcast(state)
        state = maybe_start_llm_response(previous, state)
        {:reply, {:halt, session}, state}
    end
  end

  @impl true
  def handle_info({:tilde_llm_response, {:ok, text}}, state) do
    state = %{
      state
      | responding?: false,
        session: Session.append_event(state.session, Tilde.assistant_done(text))
    }

    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:tilde_llm_response, {:error, reason}}, state) do
    text = llm_error_message(reason)

    state = %{
      state
      | responding?: false,
        session: Session.append_event(state.session, Tilde.assistant_done(text))
    }

    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, update_in(state.subscribers, &Map.delete(&1, ref))}
  end

  defp maybe_start_llm_response(_previous, %__MODULE__{responding?: true} = state), do: state

  defp maybe_start_llm_response(previous, %__MODULE__{} = state) do
    if LLM.enabled?() and new_input_submitted?(previous, state.session) do
      server = self()
      session = state.session

      Task.start(fn -> send(server, {:tilde_llm_response, LLM.respond(session)}) end)
      %{state | responding?: true}
    else
      state
    end
  end

  defp new_input_submitted?(%Session{} = previous, %Session{} = session) do
    length(session.events) > length(previous.events) and
      last_event_type(session) == :input_submitted
  end

  defp last_event_type(%Session{events: [%Event{} | _] = events}),
    do: events |> List.last() |> Map.get(:type)

  defp last_event_type(_session), do: nil

  defp llm_error_message(:missing_openrouter_api_key),
    do: "The model is not configured yet. Set OPENROUTER_API_KEY to enable assistant replies."

  defp llm_error_message(_reason), do: "The model is unavailable right now. Please try again."

  defp broadcast(%__MODULE__{} = state) do
    message = {:tilde_session_updated, state.session.id, state.session}
    Enum.each(state.subscribers, fn {_ref, pid} -> send(pid, message) end)
  end

  defp pop_subscriber_refs(subscribers, pid) do
    {matching, remaining} = Enum.split_with(subscribers, fn {_ref, sub_pid} -> sub_pid == pid end)
    {Enum.map(matching, &elem(&1, 0)), Map.new(remaining)}
  end
end
