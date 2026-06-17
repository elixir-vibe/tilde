defmodule Tilde.Demo.Live do
  @moduledoc """
  Self-contained LiveView demo for Tilde.

  Mount this LiveView in a Phoenix router while dogfooding the package:

      live "/tilde", Tilde.Demo.Live

  It exercises the semantic session model, the LiveView renderer, tool
  expansion, choice selection, input submission, widgets, and footer status.
  """

  use Phoenix.LiveView

  import Tilde.Transport.Live.Console
  import Tilde.Transport.Live.WidgetRenderer

  alias Tilde.Core.{Index, Interaction, Session}
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer
  alias Tilde.Transport.Live.Interaction, as: LiveInteraction
  alias Tilde.Transport.Live.Outcome, as: LiveOutcome

  @impl true
  def mount(%{"session_id" => _session_id} = params, _session, socket) do
    {server, session_id} = session_server(params)
    {:ok, _pid} = SessionServer.ensure_started(server, session: demo_session(id: session_id))

    session =
      if connected?(socket),
        do: SessionServer.subscribe(server),
        else: SessionServer.get_session(server)

    {:ok,
     assign(socket,
       mode: :session,
       session_server: server,
       session: session,
       index: nil,
       running?: false
     )}
  end

  def mount(_params, _session, socket) do
    {:ok, _pid} = SessionRegistry.ensure_started()

    {:ok,
     assign(socket,
       mode: :index,
       session_server: nil,
       session: nil,
       index: Index.new(),
       running?: false
     )}
  end

  @impl true
  def render(%{mode: :index} = assigns) do
    ~H"""
    <.widgets widgets={Tilde.Index.View.widgets(@index)} />
    """
  end

  def render(assigns) do
    ~H"""
    <.console
      session={@session}
      input={@session.input.value}
      running?={@running?}
      footer_right="/help · /showcase · /new"
    />
    """
  end

  @impl true
  def handle_event(event, params, %{assigns: %{mode: :index, index: %Index{} = index}} = socket) do
    case LiveInteraction.index(event, params, index) do
      %Interaction{} = interaction -> apply_index_interaction(socket, interaction)
      nil -> {:noreply, socket}
    end
  end

  def handle_event(event, params, socket) do
    case LiveInteraction.session(event, params) do
      %Interaction{type: :interrupt} = interaction ->
        {:noreply, socket} = apply_session_interaction(socket, interaction)
        {:noreply, assign(socket, running?: false)}

      %Interaction{} = interaction ->
        apply_session_interaction(socket, interaction)

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:tilde_session_updated, _session_id, %Session{} = session},
        %{assigns: %{mode: :session}} = socket
      ) do
    {:noreply, assign(socket, session: session)}
  end

  def handle_info({:tilde_session_updated, _session_id, %Session{}}, socket),
    do: {:noreply, socket}

  defp session_server(%{"session_id" => session_id}) do
    session_id = SessionRegistry.normalize_id(session_id)
    {:ok, _pid} = SessionRegistry.ensure_started()
    {SessionRegistry.via(session_id), session_id}
  end

  @doc "Returns the initial semantic session used by the demo LiveView."
  @spec demo_session(keyword()) :: Session.t()
  def demo_session(opts \\ []) do
    id = Keyword.get(opts, :id, "tilde_demo")

    Tilde.session(id: id)
    |> Session.append_event(
      Tilde.assistant_done(
        "Type `/showcase` to load the semantic console showcase, or `/help` for commands.",
        id: "evt_demo_welcome"
      )
    )
  end

  defp apply_session_interaction(socket, %Interaction{} = interaction) do
    {:cont, session, effects} =
      SessionServer.apply_interaction(socket.assigns.session_server, interaction)

    socket =
      socket
      |> assign(session: session)
      |> apply_outcomes(effects)

    {:noreply, socket}
  end

  defp apply_index_interaction(socket, %Interaction{} = interaction) do
    {:cont, index, effects} = Index.apply_interaction(socket.assigns.index, interaction)

    socket =
      socket
      |> assign(index: index)
      |> apply_outcomes(effects)

    {:noreply, socket}
  end

  defp apply_outcomes(socket, outcomes) do
    LiveOutcome.apply(socket, outcomes, session_path: &session_path/1)
  end

  defp session_path(id), do: "/tilde/#{id}"
end
