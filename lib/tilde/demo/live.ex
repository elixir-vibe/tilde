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

  alias Tilde.Command
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
    session =
      SessionServer.update_session(socket.assigns.session_server, &Session.toggle_expand(&1, id))

    {:noreply, assign(socket, session: session)}
  end

  def handle_event(
        "tilde:select_choice",
        %{"block-id" => block_id, "option-id" => option_id},
        socket
      ) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.select_choice(&1, block_id, option_id)
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:choice_action", %{"action-id" => action_id}, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.put_status(&1, "choice", action_id)
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:input_changed", %{"input" => input}, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.append_event(&1, Tilde.input_changed(input))
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:complete_input", params, socket) do
    input = Map.get(params, "insert") || complete_input(Map.get(params, "input", ""))

    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.append_event(&1, Tilde.input_changed(input))
      )

    socket =
      if input != Map.get(params, "input"),
        do: push_event(socket, "tilde:input_completed", %{insert: input}),
        else: socket

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:suggest_next", _params, socket) do
    update_suggestions(socket, &Session.select_next_suggestion/1)
  end

  def handle_event("tilde:suggest_previous", _params, socket) do
    update_suggestions(socket, &Session.select_previous_suggestion/1)
  end

  def handle_event("tilde:suggest_cancel", _params, socket) do
    update_suggestions(socket, &Session.cancel_suggestions/1)
  end

  def handle_event("tilde:suggest_accept", _params, socket) do
    session =
      SessionServer.update_session(socket.assigns.session_server, fn session ->
        case Session.accept_suggestion(session) do
          {:ok, session} -> session
          :error -> session
        end
      end)

    socket = push_event(socket, "tilde:input_completed", %{insert: session.input.value})
    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:suggest_submit", _params, socket) do
    submitted_input = submitted_suggestion_input(socket.assigns.session)

    session =
      SessionServer.update_session(socket.assigns.session_server, fn session ->
        case Session.submit_suggestion(session) do
          {:ok, session} -> session
          :error -> session
        end
      end)

    socket =
      socket
      |> maybe_apply_submitted_suggestion(submitted_input, session)
      |> push_event("tilde:input_completed", %{insert: session.input.value})

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:submit", %{"input" => input}, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.append_event(&1, Tilde.input_submitted(input))
      )

    socket =
      input
      |> Command.parse()
      |> command_effects(session)
      |> apply_transport_effects(socket)

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:interrupt", _params, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.put_status(&1, "runtime", "interrupted")
      )

    {:noreply, assign(socket, session: session, running?: false)}
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

  defp update_suggestions(socket, fun) when is_function(fun, 1) do
    session = SessionServer.update_session(socket.assigns.session_server, fun)
    {:noreply, assign(socket, session: session)}
  end

  defp command_effects({:ok, %Command{} = command}, %Session{} = session),
    do: Command.run(command, session, [])

  defp command_effects(:error, _session), do: []

  defp apply_transport_effects(effects, socket) do
    Enum.reduce(effects, socket, fn
      %Tilde.Command.Effect.NewSession{id: id}, socket ->
        push_navigate(socket, to: session_path(id))

      %Tilde.Command.Effect.AttachSession{id: id}, socket ->
        push_navigate(socket, to: session_path(id))

      %Tilde.Command.Effect.DetachSession{}, socket ->
        push_navigate(socket, to: "/")

      _effect, socket ->
        socket
    end)
  end

  defp apply_index_interaction(socket, %Interaction{} = interaction) do
    {:cont, index, effects} = Index.apply_interaction(socket.assigns.index, interaction)

    socket =
      socket
      |> assign(index: index)
      |> apply_index_effects(effects)

    {:noreply, socket}
  end

  defp apply_index_effects(socket, effects) do
    Enum.reduce(effects, socket, fn
      %InteractionEffect{type: :complete_input, payload: %{input: input}}, socket ->
        push_event(socket, "tilde:input_completed", %{insert: input})

      %InteractionEffect{type: :open_session, payload: %{id: id}}, socket ->
        push_navigate(socket, to: session_path(id))
    end)
  end

  defp submitted_suggestion_input(%Session{} = session) do
    case Session.command_suggestions(session) do
      nil -> nil
      suggest -> Tilde.Core.Suggest.accept(suggest)
    end
  end

  defp maybe_apply_submitted_suggestion(socket, input, session) when is_binary(input) do
    if String.ends_with?(input, " ") do
      socket
    else
      input
      |> Command.parse()
      |> command_effects(session)
      |> apply_transport_effects(socket)
    end
  end

  defp maybe_apply_submitted_suggestion(socket, _input, _session), do: socket

  defp session_path(id), do: "/tilde/#{id}"

  defp complete_input(input), do: Command.completion(input) || input
end
