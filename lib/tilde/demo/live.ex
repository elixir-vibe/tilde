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
  alias Tilde.Core.Interaction.Effect, as: InteractionEffect
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer

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
  def handle_event("tilde:toggle_expand", _params, %{assigns: %{mode: :index}} = socket),
    do: {:noreply, socket}

  def handle_event(
        "tilde:input_changed",
        %{"input" => "n"},
        %{assigns: %{mode: :index, index: %Index{input: %Tilde.Core.Input{value: ""}}}} = socket
      ) do
    apply_index_interaction(socket, Interaction.new(:new_shortcut))
  end

  def handle_event(
        "tilde:input_changed",
        %{"input" => input},
        %{assigns: %{mode: :index}} = socket
      ) do
    apply_index_interaction(socket, Interaction.input_changed(input))
  end

  def handle_event(
        "tilde:complete_input",
        %{"insert" => insert},
        %{assigns: %{mode: :index}} = socket
      ) do
    apply_index_interaction(socket, Interaction.complete_input(insert))
  end

  def handle_event("tilde:suggest_next", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:suggest_next))
  end

  def handle_event("tilde:suggest_previous", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:suggest_previous))
  end

  def handle_event("tilde:suggest_cancel", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:suggest_cancel))
  end

  def handle_event("tilde:suggest_accept", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:suggest_accept))
  end

  def handle_event("tilde:suggest_submit", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:suggest_submit))
  end

  def handle_event("tilde:submit", %{"input" => input}, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.submit(input))
  end

  def handle_event("tilde:interrupt", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:interrupt))
  end

  def handle_event("tilde:index_new", _params, %{assigns: %{mode: :index}} = socket) do
    apply_index_interaction(socket, Interaction.new(:new_shortcut))
  end

  def handle_event(
        "tilde:index_keydown",
        %{"key" => "Enter"},
        %{assigns: %{mode: :index}} = socket
      ) do
    apply_index_interaction(socket, Interaction.new(:suggest_submit))
  end

  def handle_event(
        "tilde:index_keydown",
        %{"key" => "n", "value" => ""},
        %{assigns: %{mode: :index}} = socket
      ) do
    handle_event("tilde:index_new", %{}, socket)
  end

  def handle_event("tilde:index_keydown", _params, %{assigns: %{mode: :index}} = socket),
    do: {:noreply, socket}

  def handle_event("tilde:toggle_expand", %{"id" => id}, socket) do
    apply_session_interaction(socket, Interaction.new(:toggle_expand, %{id: id}))
  end

  def handle_event(
        "tilde:select_choice",
        %{"block-id" => block_id, "option-id" => option_id},
        socket
      ) do
    apply_session_interaction(
      socket,
      Interaction.new(:select_choice, %{block_id: block_id, option_id: option_id})
    )
  end

  def handle_event("tilde:choice_action", %{"action-id" => action_id}, socket) do
    apply_session_interaction(socket, Interaction.new(:choice_action, %{action_id: action_id}))
  end

  def handle_event("tilde:input_changed", %{"input" => input}, socket) do
    apply_session_interaction(socket, Interaction.input_changed(input))
  end

  def handle_event("tilde:complete_input", params, socket) do
    payload = %{
      input: Map.get(params, "input", ""),
      insert: Map.get(params, "insert")
    }

    apply_session_interaction(socket, Interaction.new(:complete_input, payload))
  end

  def handle_event("tilde:suggest_next", _params, socket) do
    apply_session_interaction(socket, Interaction.new(:suggest_next))
  end

  def handle_event("tilde:suggest_previous", _params, socket) do
    apply_session_interaction(socket, Interaction.new(:suggest_previous))
  end

  def handle_event("tilde:suggest_cancel", _params, socket) do
    apply_session_interaction(socket, Interaction.new(:suggest_cancel))
  end

  def handle_event("tilde:suggest_accept", _params, socket) do
    apply_session_interaction(socket, Interaction.new(:suggest_accept))
  end

  def handle_event("tilde:suggest_submit", _params, socket) do
    apply_session_interaction(socket, Interaction.new(:suggest_submit))
  end

  def handle_event("tilde:submit", %{"input" => input}, socket) do
    apply_session_interaction(socket, Interaction.submit(input))
  end

  def handle_event("tilde:interrupt", _params, socket) do
    {:noreply, socket} = apply_session_interaction(socket, Interaction.new(:interrupt))
    {:noreply, assign(socket, running?: false)}
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
      |> apply_interaction_effects(effects)

    {:noreply, socket}
  end

  defp apply_index_interaction(socket, %Interaction{} = interaction) do
    {:cont, index, effects} = Index.apply_interaction(socket.assigns.index, interaction)

    socket =
      socket
      |> assign(index: index)
      |> apply_index_effects(effects)

    {:noreply, socket}
  end

  defp apply_index_effects(socket, effects), do: apply_interaction_effects(socket, effects)

  defp apply_interaction_effects(socket, effects) do
    Enum.reduce(effects, socket, fn
      %InteractionEffect{type: :complete_input, payload: %{input: input}}, socket ->
        push_event(socket, "tilde:input_completed", %{insert: input})

      %InteractionEffect{type: :open_session, payload: %{id: id}}, socket ->
        push_navigate(socket, to: session_path(id))

      %InteractionEffect{type: :open_index}, socket ->
        push_navigate(socket, to: "/")

      %InteractionEffect{type: :show_session_info}, socket ->
        socket
    end)
  end

  defp session_path(id), do: "/tilde/#{id}"
end
