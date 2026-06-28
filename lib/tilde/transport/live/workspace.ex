defmodule Tilde.Transport.Live.Workspace do
  @moduledoc """
  LiveView components for Tilde's persistent read-only workspace pane.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Footer

  alias Tilde.Core.{FileSymbol, Shortcuts}
  alias Tilde.Core.Workspace

  attr(:workspace, Workspace, required: true)
  attr(:view, :atom, default: :files)
  attr(:symbols, :list, default: [])
  attr(:active_symbol_line, :integer, default: nil)
  attr(:actions, :list, default: [])

  def file_pane(assigns) do
    assigns =
      assigns
      |> assign(:sections, sections(assigns.workspace))
      |> assign(:symbol_sections, symbol_sections(assigns.symbols))
      |> assign(:view_actions, view_actions())

    ~H"""
    <aside class="workspace" aria-label="workspace context">
      <header class="header">
        <span class="title">workspace</span>
        <nav class="views actions" aria-label="workspace views">
          <.action
            :for={action <- @view_actions}
            event={action.event}
            label={action.label}
            shortcut={action.shortcut}
            kind={view_action_kind(@view, action.view)}
          />
        </nav>
      </header>

      <div :if={@view == :files and @sections == []} class="empty">
        No active files yet.
        <span>Files read or changed by this session will appear here.</span>
      </div>

      <div :if={@view == :symbols and @symbols == []} class="empty">
        No current-file symbols.
        <span>Open an Elixir source file to see its outline. Workspace-wide symbols will come later.</span>
      </div>

      <div :if={@view == :files and @sections != []} class="sections">
        <section :for={section <- @sections} class="section" aria-label={section.title}>
          <header class="section_header">
            <span>{section.title}</span>
            <span>{length(section.files)}</span>
          </header>

          <div class="files" role="list">
            <%= for row <- section.rows do %>
              <div
                :if={row.node.kind == :directory}
                class={["file", "directory"]}
                style={depth_style(row.depth)}
                role="listitem"
              >
                <span class="marks" aria-hidden="true"> </span>
                <span class="path">{row.node.name}</span>
              </div>
              <button
                :if={row.node.kind == :file}
                type="button"
                class={file_classes(row.node.file, @workspace.selected_path, @workspace.focused_path)}
                style={depth_style(row.depth)}
                data-path={row.node.file.path}
                data-focused={row.node.file.path == @workspace.focused_path}
                role="listitem"
                title={file_title(row.node.file)}
                phx-click="tilde:workspace:open_file"
                phx-value-path={row.node.file.path}
              >
                <span class="marks" aria-label={mark_label(row.node.file)}>{marks(row.node.file)}</span>
                <span class="path">{row.node.name}</span>
              </button>
            <% end %>
          </div>
        </section>
      </div>

      <div :if={@view == :symbols and @symbols != []} class="sections symbols">
        <section :for={section <- @symbol_sections} class="section" aria-label={section.title}>
          <header class="section_header">
            <span>{section.title}</span>
            <span>{length(section.symbols)}</span>
          </header>

          <div class="files" role="list">
            <button
              :for={symbol <- section.symbols}
              type="button"
              class={symbol_classes(symbol, @active_symbol_line)}
              role="listitem"
              title={symbol_title(symbol)}
              phx-click="tilde:buffer:jump_symbol"
              phx-value-line={symbol.line}
            >
              <span class="marks" aria-label={to_string(symbol.kind)}>{symbol_mark(symbol.kind)}</span>
              <span class="path">{symbol.name}</span>
              <span class="line" aria-label={"line #{symbol.line}"}>{symbol.line}</span>
            </button>
          </div>
        </section>
      </div>

      <.footer :if={@actions != []} actions={@actions} />
    </aside>
    """
  end

  defp sections(%Workspace{} = workspace) do
    Enum.map(Workspace.file_sections(workspace), fn section ->
      section
      |> Map.from_struct()
      |> Map.put(:rows, tree_rows(section.tree))
    end)
  end

  defp tree_rows(nodes, depth \\ 0) do
    Enum.flat_map(nodes, fn node ->
      [%{node: node, depth: depth} | tree_rows(node.children, depth + 1)]
    end)
  end

  defp symbol_sections(symbols) do
    [
      %{title: "modules", symbols: Enum.filter(symbols, &(&1.kind == :module))},
      %{
        title: "functions",
        symbols: Enum.filter(symbols, &(&1.kind in [:function, :macro, :delegate]))
      },
      %{
        title: "types",
        symbols: Enum.filter(symbols, &(&1.kind in [:struct, :type, :callback, :attribute]))
      }
    ]
    |> Enum.reject(&(&1.symbols == []))
  end

  defp file_classes(%Workspace.File{} = file, selected_path, focused_path) do
    [
      "file",
      file.path == selected_path && "selected",
      file.path == focused_path && "focused",
      file.git_status != :clean && "changed",
      git_status_class(file.git_status),
      file.session_state != :untouched && file.session_state,
      not file.previewable? && "muted"
    ]
  end

  defp git_status_class(:clean), do: nil
  defp git_status_class(status), do: "git-#{status}"

  defp depth_style(depth), do: "--depth: #{depth}"

  defp file_title(%Workspace.File{} = file),
    do: [file.path, mark_label(file)] |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")

  defp marks(%Workspace.File{} = file), do: Workspace.File.marks(file)

  defp mark_label(%Workspace.File{} = file) do
    [session_label(file.session_state), git_label(file.git_status)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp session_label(:modified), do: "modified in session"
  defp session_label(:read), do: "read in session"
  defp session_label(_state), do: ""

  defp git_label(:clean), do: ""
  defp git_label(status), do: "git #{status}"

  defp view_actions do
    [
      view_action(:files, "tilde.workspace.view_files"),
      view_action(:symbols, "tilde.workspace.view_symbols")
    ]
  end

  defp view_action(view, shortcut) do
    %{
      view: view,
      event: "tilde:workspace:view_#{view}",
      label: Shortcuts.label(shortcut),
      shortcut: shortcut
    }
  end

  defp view_action_kind(current_view, current_view), do: :selected
  defp view_action_kind(_current_view, _view), do: :normal

  defp symbol_classes(%FileSymbol{} = symbol, active_symbol_line) do
    [
      "file",
      "symbol",
      symbol.kind,
      symbol.line == active_symbol_line && "selected"
    ]
  end

  defp symbol_title(%FileSymbol{} = symbol) do
    "#{symbol.kind} · #{symbol.name} · line #{symbol.line}"
  end

  defp symbol_mark(:module), do: "M"
  defp symbol_mark(:function), do: "ƒ"
  defp symbol_mark(:macro), do: "μ"
  defp symbol_mark(:delegate), do: "→"
  defp symbol_mark(:struct), do: "%"
  defp symbol_mark(:type), do: "T"
  defp symbol_mark(:callback), do: "C"
  defp symbol_mark(:attribute), do: "@"
  defp symbol_mark(_kind), do: "•"
end
