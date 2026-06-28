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

  alias Tilde.Core.Index
  alias Tilde.Core.Interaction
  alias Tilde.Core.Palette
  alias Tilde.Core.Review
  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File
  alias Tilde.Core.Session
  alias Tilde.Core.Shortcuts
  alias Tilde.Core.Workspace
  alias Tilde.Runtime.WorkspaceFiles
  alias Tilde.Session.Loader, as: SessionLoader
  alias Tilde.Session.Registry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer
  alias Tilde.Transport.Live.Interaction, as: LiveInteraction
  alias Tilde.Transport.Live.Outcome, as: LiveOutcome

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

    workspace = WorkspaceFiles.workspace(session)

    {:ok,
     socket
     |> assign(
       mode: :session,
       session_server: server,
       session: session,
       workspace: workspace,
       workspace_mode: :chat,
       workspace_view: :files,
       open_file: nil,
       active_symbol_line: nil,
       review: demo_review(workspace),
       review_open?: true,
       active_review_comment_id: nil,
       palette: Palette.new(),
       index: nil,
       running?: false
     )
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
    {:noreply, open_workspace_file(socket, path)}
  end

  def handle_event("tilde:session:chat", _params, socket) do
    {:noreply, assign(socket, workspace_mode: :chat, open_file: nil, active_symbol_line: nil)}
  end

  def handle_event("tilde:workspace:show", params, socket) do
    {:noreply,
     socket
     |> assign(workspace_mode: :workspace)
     |> assign_workspace_view(params)}
  end

  def handle_event("tilde:workspace:view_files", _params, socket) do
    {:noreply, assign(socket, workspace_view: :files)}
  end

  def handle_event("tilde:workspace:view_symbols", _params, socket) do
    {:noreply, assign(socket, workspace_view: :symbols)}
  end

  def handle_event("tilde:review:jump_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, jump_review_comment(socket, comment_id)}
  end

  def handle_event("tilde:review:focus", _params, socket) do
    {:noreply, focus_review(socket)}
  end

  def handle_event("tilde:review:resolve_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, update_review_comment(socket, comment_id, :resolved)}
  end

  def handle_event("tilde:review:reopen_comment", %{"comment-id" => comment_id}, socket) do
    {:noreply, update_review_comment(socket, comment_id, :open)}
  end

  def handle_event("tilde:palette:change", %{"query" => query}, socket) do
    {:noreply,
     assign(socket,
       palette:
         Palette.query(
           socket.assigns.palette,
           socket.assigns.workspace,
           socket.assigns.open_file,
           query
         )
     )}
  end

  def handle_event("tilde:palette:mode", %{"mode" => mode}, socket) do
    {:noreply,
     assign(socket,
       palette:
         Palette.switch_mode(
           socket.assigns.palette,
           mode,
           socket.assigns.workspace,
           socket.assigns.open_file
         )
     )}
  end

  def handle_event("tilde:palette:accept", params, socket) do
    {:noreply, accept_palette(socket, params)}
  end

  def handle_event("tilde:palette:select", params, socket) do
    {:noreply, accept_palette(socket, params)}
  end

  def handle_event("tilde:shortcut", %{"key" => key}, socket) do
    {:noreply, apply_shortcut(socket, key)}
  end

  def handle_event("tilde:shortcut", _params, socket), do: {:noreply, socket}

  def handle_event("tilde:buffer:jump_symbol", %{"line" => line}, socket) do
    {:noreply, assign(socket, workspace_mode: :file, active_symbol_line: parse_line(line))}
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

  @doc "Returns the demo review used by mirrored web and SSH/TUI surfaces."
  @spec demo_review(Workspace.t()) :: Review.t()
  def demo_review(%Workspace{} = workspace) do
    paths =
      workspace
      |> review_paths()
      |> Enum.take(3)

    files =
      paths
      |> Enum.with_index()
      |> Enum.map(fn {path, index} ->
        File.new(
          path: path,
          status: :needs_changes,
          comments: [demo_comment(path, index)]
        )
      end)

    Review.new(id: "working-tree", title: "working tree review", files: files)
  end

  defp review_paths(%Workspace{} = workspace) do
    relevant_paths =
      workspace
      |> Workspace.file_sections()
      |> Enum.flat_map(& &1.files)
      |> Enum.map(& &1.path)

    case relevant_paths do
      [] -> fallback_review_paths(workspace)
      paths -> paths
    end
  end

  defp fallback_review_paths(%Workspace{files: files}) do
    preferred = ["lib/tilde/demo/live.ex", "lib/tilde/core/palette.ex", "mix.exs"]
    paths = Enum.map(files, & &1.path)

    case paths do
      [] -> preferred
      paths -> preferred |> Enum.filter(&(&1 in paths)) |> Kernel.++(paths) |> Enum.uniq()
    end
  end

  defp demo_comment(path, index) do
    severity = Enum.at([:issue, :warning, :note], index, :note)

    Comment.new(
      id: "review-#{index + 1}",
      path: path,
      line: index + 1,
      severity: severity,
      body: demo_review_body(severity)
    )
  end

  defp demo_review_body(:issue), do: "Check this change before shipping."
  defp demo_review_body(:warning), do: "Confirm the behavior is covered by a focused test."
  defp demo_review_body(:note), do: "Consider whether this belongs in shared UI vocabulary."

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
    workspace =
      session
      |> WorkspaceFiles.workspace()
      |> Workspace.preserve_navigation(socket.assigns[:workspace])

    assign(socket,
      session: session,
      workspace: workspace,
      palette: Palette.refresh(socket.assigns[:palette], workspace, socket.assigns[:open_file])
    )
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

  defp apply_shortcut(socket, key) when is_binary(key) do
    socket
    |> shortcut_scope()
    |> Shortcuts.match(key)
    |> apply_shortcut_id(socket)
  end

  defp apply_shortcut(socket, _key), do: socket

  defp apply_shortcut_id("tilde.workspace.view_files", socket),
    do: assign(socket, workspace_view: :files)

  defp apply_shortcut_id("tilde.workspace.view_symbols", socket),
    do: assign(socket, workspace_view: :symbols)

  defp apply_shortcut_id("tilde.session.chat", socket),
    do: assign(socket, workspace_mode: :chat, open_file: nil, active_symbol_line: nil)

  defp apply_shortcut_id("tilde.review.focus", socket), do: focus_review(socket)

  defp apply_shortcut_id("tilde.workspace.focus_previous", socket),
    do: focus_workspace_file(socket, :previous)

  defp apply_shortcut_id("tilde.workspace.focus_next", socket),
    do: focus_workspace_file(socket, :next)

  defp apply_shortcut_id("tilde.workspace.open_focused", socket),
    do: open_focused_workspace_file(socket)

  defp apply_shortcut_id("tilde.palette.open", socket), do: open_palette(socket)

  defp apply_shortcut_id("tilde.palette.mode_files", socket),
    do: switch_palette_mode(socket, :files)

  defp apply_shortcut_id("tilde.palette.mode_symbols", socket),
    do: switch_palette_mode(socket, :symbols)

  defp apply_shortcut_id("tilde.palette.close", socket), do: close_palette(socket)

  defp apply_shortcut_id("tilde.palette.previous", socket),
    do: update(socket, :palette, &Palette.move(&1, :previous))

  defp apply_shortcut_id("tilde.palette.next", socket),
    do: update(socket, :palette, &Palette.move(&1, :next))

  defp apply_shortcut_id("tilde.palette.accept", socket), do: accept_palette(socket, %{})
  defp apply_shortcut_id(_shortcut, socket), do: socket

  defp open_palette(socket) do
    assign(socket,
      palette: Palette.open_files(socket.assigns.workspace, socket.assigns.palette.query)
    )
  end

  defp close_palette(socket),
    do: assign(socket, palette: %{socket.assigns.palette | open?: false})

  defp switch_palette_mode(socket, mode) do
    assign(socket,
      palette:
        Palette.switch_mode(
          socket.assigns.palette,
          mode,
          socket.assigns.workspace,
          socket.assigns.open_file
        )
    )
  end

  defp accept_palette(socket, params) do
    palette = select_palette_index(socket.assigns.palette, params)

    case Palette.selected_item(palette) do
      %{action: %{type: :open_file, path: path}} ->
        open_workspace_file(assign(socket, palette: palette), path)

      %{action: %{type: :jump_symbol, line: line}} ->
        assign(socket,
          palette: %{palette | open?: false},
          workspace_mode: :file,
          workspace_view: :symbols,
          active_symbol_line: line
        )

      _item ->
        assign(socket, palette: palette)
    end
  end

  defp select_palette_index(%Palette{} = palette, %{"index" => index}) do
    case Integer.parse(index) do
      {index, ""} -> %{palette | selected_index: max(index, 0)}
      _other -> palette
    end
  end

  defp select_palette_index(%Palette{} = palette, _params), do: palette

  defp open_workspace_file(socket, path) when is_binary(path) do
    workspace = %{socket.assigns.workspace | selected_path: path, focused_path: path}
    open_file = WorkspaceFiles.open_file(workspace, path)

    assign(socket,
      workspace: workspace,
      palette: %{socket.assigns.palette | open?: false},
      workspace_mode: :file,
      workspace_view: :symbols,
      open_file: open_file,
      active_symbol_line: nil,
      active_review_comment_id: nil
    )
  end

  defp jump_review_comment(socket, comment_id) do
    case Review.find_comment(socket.assigns.review, comment_id) do
      %{path: path, line: line, id: id} ->
        open_workspace_file_at_line(socket, path, line, id)

      nil ->
        socket
    end
  end

  defp focus_review(socket) do
    socket.assigns.review
    |> Review.focused_comment_id(socket.assigns.active_review_comment_id)
    |> case do
      nil -> assign(socket, review_open?: true)
      comment_id -> socket |> assign(review_open?: true) |> jump_review_comment(comment_id)
    end
  end

  defp update_review_comment(socket, comment_id, :resolved) do
    assign(socket, review: Review.resolve_comment(socket.assigns.review, comment_id))
  end

  defp update_review_comment(socket, comment_id, :open) do
    assign(socket, review: Review.reopen_comment(socket.assigns.review, comment_id))
  end

  defp open_workspace_file_at_line(socket, path, line, comment_id) do
    workspace = %{socket.assigns.workspace | selected_path: path, focused_path: path}
    open_file = WorkspaceFiles.open_file(workspace, path)

    assign(socket,
      workspace: workspace,
      palette: %{socket.assigns.palette | open?: false},
      workspace_mode: :file,
      workspace_view: :files,
      open_file: open_file,
      active_symbol_line: line,
      active_review_comment_id: comment_id
    )
  end

  defp focus_workspace_file(socket, direction) do
    assign(socket, workspace: Workspace.focus_file(socket.assigns.workspace, direction))
  end

  defp open_focused_workspace_file(socket) do
    focused_path = socket.assigns.workspace.focused_path

    if focused_path in Workspace.visible_file_paths(socket.assigns.workspace) do
      open_workspace_file(socket, focused_path)
    else
      socket
    end
  end

  defp shortcut_scope(%{assigns: assigns}), do: shortcut_scope(assigns)
  defp shortcut_scope(%{palette: %Palette{open?: true}}), do: :palette
  defp shortcut_scope(%{workspace_mode: :file}), do: :buffer
  defp shortcut_scope(%{workspace_mode: :workspace}), do: :workspace
  defp shortcut_scope(_assigns), do: :chat

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

  defp assign_workspace_view(socket, %{"view" => "files"}),
    do: assign(socket, workspace_view: :files)

  defp assign_workspace_view(socket, %{"view" => "symbols"}),
    do: assign(socket, workspace_view: :symbols)

  defp assign_workspace_view(socket, _params), do: socket

  defp open_file_path(%{path: path}) when is_binary(path), do: path
  defp open_file_path(_open_file), do: nil

  defp symbols(%{symbols: symbols}) when is_list(symbols), do: symbols
  defp symbols(_open_file), do: []

  defp parse_line(line) when is_binary(line) do
    case Integer.parse(line) do
      {line, ""} -> line
      _ -> nil
    end
  end

  defp parse_line(_line), do: nil

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
