defmodule Tilde.Demo.Live do
  @moduledoc """
  Self-contained LiveView demo for Tilde.

  Mount this LiveView in a Phoenix router while dogfooding the package:

      live "/", Tilde.Demo.Live
      live "/sessions/:session_id", Tilde.Demo.Live

  It exercises the semantic session model, the LiveView renderer, tool
  expansion, choice selection, input submission, widgets, and footer status.
  """

  use Phoenix.LiveView

  import Tilde.Transport.Live.Console
  import Tilde.Transport.Live.Palette
  import Tilde.Transport.Live.Review
  import Tilde.Transport.Live.WidgetRenderer
  import Tilde.Transport.Live.Workspace
  import Tilde.Transport.Live.WorkspaceFile

  alias Tilde.Core.Interaction
  alias Tilde.Core.Session
  alias Tilde.Core.Shortcuts
  alias Tilde.Index
  alias Tilde.Session.Loader, as: SessionLoader
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer
  alias Tilde.Transport.Live.Interaction, as: LiveInteraction
  alias Tilde.Transport.Live.Outcome, as: LiveOutcome
  alias Tilde.Workbench

  @impl true
  def mount(%{"session_id" => _session_id} = params, _session, socket) do
    {server, session_id} = session_server(params)

    {:ok, _pid} =
      SessionServer.ensure_started(server,
        session:
          SessionLoader.load_or_new(session_id, new: fn -> demo_session(id: session_id) end)
      )

    session =
      if connected?(socket) do
        session = SessionServer.subscribe(server)
        maybe_store_request_origin(server, session, socket)
      else
        SessionServer.get_session(server)
      end

    workbench = Workbench.new(session)

    {:ok,
     socket
     |> assign(
       mode: :session,
       session_server: server,
       index: nil,
       running?: false
     )
     |> assign(Workbench.to_map(workbench))
     |> assign_devtools()}
  end

  def mount(_params, _session, socket) do
    {:ok, _pid} = SessionRegistry.ensure_started()

    {:ok,
     socket
     |> assign(
       mode: :index,
       session_server: nil,
       session: nil,
       index: Index.new(),
       running?: false
     )
     |> assign_devtools()}
  end

  @impl true
  def render(%{mode: :index} = assigns) do
    ~H"""
    <div class={["tilde", "devshell", @dev_grid? && "grid"]} data-dev-grid={@dev_grid?}>
      <div class="main">
        <.widgets
          widgets={Tilde.Index.View.widgets(@index)}
          devtools?={@devtools?}
          dev_grid?={@dev_grid?}
          dev_raw={inspectable(assigns)}
        />
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      class={[
        "tilde",
        "devshell",
        "workbench",
        @workspace_mode == :workspace && "workspace-open",
        @review_open? && "review-open",
        @dev_grid? && "grid"
      ]}
      id="tilde-workbench"
      data-dev-grid={@dev_grid?}
      data-shortcut-scope={shortcut_scope(assigns)}
      data-shortcuts={shortcut_bindings()}
      phx-hook="TildeShortcuts"
    >
      <.file_pane
        workspace={@workspace}
        view={@workspace_view}
        symbols={symbols(@open_file)}
        active_symbol_line={@active_symbol_line}
        actions={workspace_actions()}
      />
      <.palette palette={@palette} />
      <div class="main">
        <.file_surface
          :if={@workspace_mode == :file}
          file={@open_file}
          scroll_line={@active_symbol_line}
          actions={file_actions()}
        />
        <.console
          :if={@workspace_mode == :chat}
          session={@session}
          input={@session.input.value}
          running?={@running?}
          footer_commands={footer_commands()}
          footer_actions={chat_actions()}
          class="embedded"
          devtools?={@devtools?}
          dev_grid?={@dev_grid?}
          dev_raw={inspectable(assigns)}
        />
      </div>
      <.review_pane
        :if={@review_open?}
        review={@review}
        current_path={open_file_path(@open_file)}
        active_comment_id={@active_review_comment_id}
      />
    </div>
    """
  end

  @impl true
  def handle_event("tilde:dev_toggle_grid", _params, socket) do
    {:noreply, toggle_dev(socket, :dev_grid?)}
  end

  def handle_event("tilde:workspace:open_file", %{"path" => path}, socket) do
    {:noreply, apply_workbench_action(socket, {:open_file, path})}
  end

  def handle_event("tilde:session:chat", _params, socket) do
    {:noreply, apply_workbench_action(socket, :show_chat)}
  end

  def handle_event("tilde:workspace:show", params, socket) do
    {:noreply, apply_workbench_action(socket, {:show_workspace, workspace_view(params)})}
  end

  def handle_event("tilde:workspace:view_files", _params, socket) do
    {:noreply, apply_workbench_action(socket, {:set_workspace_view, :files})}
  end

  def handle_event("tilde:workspace:view_symbols", _params, socket) do
    {:noreply, apply_workbench_action(socket, {:set_workspace_view, :symbols})}
  end

  def handle_event("tilde:review:jump_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, apply_workbench_action(socket, {:jump_review_comment, comment_id})}
  end

  def handle_event("tilde:review:focus", _params, socket) do
    {:noreply, apply_workbench_action(socket, :focus_review)}
  end

  def handle_event("tilde:review:resolve_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, apply_workbench_action(socket, {:set_review_status, comment_id, :resolved})}
  end

  def handle_event("tilde:review:reopen_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, apply_workbench_action(socket, {:set_review_status, comment_id, :open})}
  end

  def handle_event("tilde:palette:change", %{"query" => query}, socket) do
    {:noreply, apply_workbench_action(socket, {:query_palette, query})}
  end

  def handle_event("tilde:palette:mode", %{"mode" => mode}, socket) do
    {:noreply, apply_workbench_action(socket, {:switch_palette_mode, mode})}
  end

  def handle_event(event, params, socket)
      when event in ["tilde:palette:accept", "tilde:palette:select"] do
    {:noreply, accept_palette(socket, params)}
  end

  def handle_event("tilde:shortcut", %{"key" => key}, socket) do
    {:noreply,
     apply_workbench_action(socket, {:shortcut, key},
       page_size: 20,
       scroll_field: :active_symbol_line
     )}
  end

  def handle_event("tilde:shortcut", _params, socket), do: {:noreply, socket}

  def handle_event("tilde:buffer:jump_symbol", %{"line" => line}, socket) do
    {:noreply, apply_workbench_action(socket, {:jump_symbol, line})}
  end

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
    {:noreply, assign_session(socket, session)}
  end

  def handle_info({:tilde_session_updated, _session_id, %Session{}}, socket),
    do: {:noreply, socket}

  defp maybe_store_request_origin(server, %Session{} = session, socket) do
    case request_origin(socket) do
      nil ->
        session

      origin ->
        SessionServer.update_session(server, fn session ->
          put_in(session.metadata[:app_referer], origin)
        end)
    end
  end

  defp request_origin(socket) do
    uri = get_connect_info(socket, :uri)
    headers = get_connect_info(socket, :x_headers) || []

    host = forwarded_header(headers, "x-forwarded-host") || uri_host(uri)
    scheme = forwarded_header(headers, "x-forwarded-proto") || uri_scheme(uri)

    if host && scheme, do: "#{scheme}://#{host}"
  end

  defp forwarded_header(headers, key) do
    headers
    |> List.keyfind(key, 0)
    |> case do
      {^key, value} -> value |> String.split(",") |> List.first() |> String.trim()
      nil -> nil
    end
  end

  defp uri_host(%URI{host: host, port: nil}) when is_binary(host), do: host

  defp uri_host(%URI{host: host, port: port, scheme: scheme}) when is_binary(host) do
    if default_port?(scheme, port), do: host, else: "#{host}:#{port}"
  end

  defp uri_host(_uri), do: nil

  defp uri_scheme(%URI{scheme: scheme}) when is_binary(scheme), do: scheme
  defp uri_scheme(_uri), do: nil

  defp default_port?("http", 80), do: true
  defp default_port?("https", 443), do: true
  defp default_port?(_scheme, _port), do: false

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
      |> assign_session(session)
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

  defp assign_session(socket, %Session{} = session) do
    workbench = socket.assigns |> Workbench.from_map() |> Workbench.refresh(session)
    assign(socket, Workbench.to_map(workbench))
  end

  defp inspectable(%{session: %Session{}, session_server: server}) when not is_nil(server) do
    %{session: session, agent_loop: agent_loop} = SessionServer.dev_snapshot(server)
    Tilde.Dev.Inspector.session(session, agent_loop)
  end

  defp inspectable(%{session: %Session{} = session}), do: Tilde.Dev.Inspector.session(session)

  defp inspectable(%{index: %Index{} = index}),
    do: inspect(index, pretty: true, limit: :infinity, width: 100)

  defp inspectable(_assigns), do: "nil"

  defp shortcut_bindings do
    Shortcuts.browser_bindings()
    |> Jason.encode!()
  end

  defp assign_devtools(socket) do
    assign(socket,
      devtools?: Tilde.Dev.enabled?(),
      dev_grid?: false
    )
  end

  defp toggle_dev(%{assigns: %{devtools?: true}} = socket, key) do
    assign(socket, key, not Map.get(socket.assigns, key, false))
  end

  defp toggle_dev(socket, _key), do: socket

  defp apply_workbench_action(socket, action, opts \\ []) do
    {workbench, effects} =
      socket.assigns
      |> Workbench.from_map()
      |> Workbench.apply_action(action, opts)

    socket
    |> assign(Workbench.to_map(workbench))
    |> apply_workbench_effects(effects)
  end

  defp apply_workbench_effects(socket, effects) do
    Enum.reduce(effects, socket, fn
      {:persist_review, review}, socket ->
        session =
          SessionServer.update_session(
            socket.assigns.session_server,
            &Tilde.Session.ReviewState.put(&1, review)
          )

        assign_session(socket, session)
    end)
  end

  defp accept_palette(socket, %{"index" => index}) do
    socket
    |> apply_workbench_action({:select_palette, index})
    |> apply_workbench_action(:accept_palette)
  end

  defp accept_palette(socket, _params),
    do: apply_workbench_action(socket, :accept_palette)

  defp shortcut_scope(%{assigns: assigns}), do: shortcut_scope(assigns)

  defp shortcut_scope(assigns) when is_map(assigns),
    do: assigns |> Workbench.from_map() |> Workbench.shortcut_scope()

  defp chat_actions do
    [workspace_mobile_action(:files)]
  end

  defp file_actions do
    [
      workspace_mobile_action(:files),
      workspace_mobile_action(:symbols),
      review_action()
    ]
  end

  defp review_action do
    %{
      event: "tilde:review:focus",
      label: Shortcuts.label("tilde.review.focus"),
      shortcut: "tilde.review.focus"
    }
  end

  defp workspace_actions do
    [mobile_action("tilde:session:chat", "chat")]
  end

  defp workspace_mobile_action(:files) do
    mobile_action("tilde:workspace:show", Shortcuts.label("tilde.workspace.view_files"),
      view: :files
    )
  end

  defp workspace_mobile_action(:symbols) do
    mobile_action("tilde:workspace:show", Shortcuts.label("tilde.workspace.view_symbols"),
      view: :symbols
    )
  end

  defp mobile_action(event, label, opts \\ []) do
    values =
      case Keyword.fetch(opts, :view) do
        {:ok, view} -> %{"phx-value-view" => to_string(view)}
        :error -> %{}
      end

    %{event: event, label: label, kind: :mobile, values: values}
  end

  defp workspace_view(%{"view" => "symbols"}), do: :symbols
  defp workspace_view(_params), do: :files

  defp open_file_path(%{path: path}) when is_binary(path), do: path
  defp open_file_path(_open_file), do: nil

  defp symbols(%{symbols: symbols}) when is_list(symbols), do: symbols
  defp symbols(_open_file), do: []

  defp footer_commands do
    labels = ["/help", "/showcase", "/new"]
    specs_by_label = Map.new(Tilde.Command.Registry.specs(), &{&1.label, &1})

    Enum.map(labels, &Map.fetch!(specs_by_label, &1))
  end

  defp apply_outcomes(socket, outcomes) do
    LiveOutcome.apply(socket, outcomes, session_path: &session_path/1)
  end

  defp session_path(id), do: "/sessions/#{id}"
end
