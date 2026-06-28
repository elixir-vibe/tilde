defmodule Tilde.Renderer.TUI.Workbench do
  @moduledoc "Terminal renderer for the session workbench chrome."

  alias Tilde.Core.FileBuffer
  alias Tilde.Core.Palette, as: CorePalette
  alias Tilde.Core.Review, as: CoreReview
  alias Tilde.Core.Session
  alias Tilde.Core.Shortcuts
  alias Tilde.Core.Workspace, as: CoreWorkspace
  alias Tilde.Renderer.TUI
  alias Tilde.Renderer.TUI.Palette, as: PaletteRenderer
  alias Tilde.Renderer.TUI.Review, as: ReviewRenderer
  alias Tilde.Renderer.TUI.TextLayout
  alias Tilde.Renderer.TUI.Theme
  alias Tilde.Renderer.TUI.Workspace, as: WorkspaceRenderer
  alias Tilde.Renderer.TUI.WorkspaceFile

  @type mode :: :chat | :file | :workspace
  @type view :: :files | :symbols

  @wide_layout_width 110
  @workspace_width 32
  @review_width 38
  @pane_gap " │ "

  @doc "Renders workspace, main surface, review, and optional palette."
  @spec render(map(), pos_integer(), pos_integer(), keyword()) :: iodata()
  def render(state, width, height, opts \\ []) when is_map(state) do
    ansi? = Keyword.get(opts, :ansi, true)
    opts = Keyword.put(opts, :ansi, ansi?)

    body =
      if wide_layout?(width, opts) do
        wide_body(state, width, height, opts)
      else
        stacked_body(state, width, height, opts)
      end

    if ansi? do
      [IO.ANSI.home(), IO.ANSI.clear(), terminal_newlines(body)]
    else
      [body, "\n"]
    end
  end

  defp wide_layout?(width, opts) do
    Keyword.get(opts, :layout, :auto) != :stacked and width >= @wide_layout_width
  end

  defp wide_body(state, width, height, opts) do
    {workspace_width, main_width, review_width} = pane_widths(width)
    palette = render_palette(state, width, opts)
    footer = render_footer(state, width, opts)
    palette_height = line_count(palette)
    footer_height = line_count(footer)
    pane_height = max(height - palette_height - footer_height - 4, 8)

    panes =
      [
        pane("workspace", render_workspace(state, workspace_width, opts), workspace_width, opts),
        pane("main", render_main(state, main_width, pane_height, opts), main_width, opts),
        pane("review", render_review(state, review_width, opts), review_width, opts)
      ]

    [Theme.title("# tilde", opts), columns(panes, pane_height), footer, palette]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> maybe_clip(height)
  end

  defp stacked_body(state, width, height, opts) do
    [
      Theme.title("# tilde", opts),
      section("workspace", render_workspace(state, width, opts), opts),
      section("main", render_main(state, width, height, opts), opts),
      section("review", render_review(state, width, opts), opts),
      render_footer(state, width, opts),
      render_palette(state, width, opts)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
    |> maybe_clip(height)
  end

  defp section(title, body, opts) do
    [Theme.muted("── #{title} ──", opts), body]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp pane(title, body, width, opts) do
    [pane_title(title, width, opts), body]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
    |> pane_lines(width)
  end

  defp pane_title(title, width, opts) do
    title = " #{title} "
    rule = String.duplicate("─", max(width - String.length(title), 0))
    Theme.muted(title <> rule, opts)
  end

  defp columns(panes, height) do
    panes
    |> Enum.map(&fit_lines(&1, height))
    |> Enum.zip()
    |> Enum.map_join("\n", fn {left, center, right} ->
      left <> @pane_gap <> center <> @pane_gap <> right
    end)
  end

  defp pane_widths(width) do
    workspace_width = @workspace_width
    review_width = if width >= 140, do: 44, else: @review_width
    gap_width = TextLayout.visible_width(@pane_gap) * 2
    main_width = max(width - workspace_width - review_width - gap_width, 40)
    {workspace_width, main_width, review_width}
  end

  defp pane_lines(body, width) do
    body
    |> lines()
    |> Enum.map(&(&1 |> TextLayout.truncate(width) |> TextLayout.pad(width)))
  end

  defp fit_lines(lines, height) do
    width = lines |> Enum.map(&TextLayout.visible_width/1) |> Enum.max(fn -> 0 end)
    visible = Enum.take(lines, height)
    visible ++ List.duplicate(String.duplicate(" ", width), max(height - length(visible), 0))
  end

  defp line_count(""), do: 0
  defp line_count(text), do: text |> lines() |> length()

  defp lines(text), do: String.split(text, "\n", trim: false)

  defp render_workspace(
         %{workspace: %CoreWorkspace{} = _workspace, workspace_view: :symbols} = state,
         width,
         opts
       ) do
    symbols = symbols(state)

    if symbols == [] do
      Theme.muted("No current-file symbols.", opts)
    else
      Enum.map_join(symbols, "\n", fn symbol ->
        symbol
        |> symbol_line(Map.get(state, :active_symbol_line), opts)
        |> truncate(width)
      end)
    end
  end

  defp render_workspace(%{workspace: %CoreWorkspace{} = workspace}, width, opts) do
    opts =
      Keyword.merge(opts,
        selected_path: workspace.selected_path,
        focused_path: workspace.focused_path
      )

    WorkspaceRenderer.render(workspace, width, opts)
  end

  defp render_workspace(_state, _width, opts), do: Theme.muted("No workspace.", opts)

  defp symbol_line(symbol, active_line, opts) do
    selected? = symbol.line == active_line
    marker = if selected?, do: "›", else: " "
    line = String.pad_leading(Integer.to_string(symbol.line), 4)
    marker <> " " <> symbol.name <> Theme.muted("  #{line}", opts)
  end

  defp render_main(
         %{workspace_mode: :file, open_file: %FileBuffer{} = file} = state,
         width,
         _height,
         opts
       ) do
    opts = Keyword.put(opts, :active_line, Map.get(state, :active_symbol_line))
    WorkspaceFile.render(file, width, opts)
  end

  defp render_main(%{session: %Session{} = session}, width, height, opts) do
    session
    |> TUI.render(
      width: width,
      height: max(height - 12, 8),
      clear?: false,
      ansi: Keyword.get(opts, :ansi, true)
    )
    |> IO.iodata_to_binary()
    |> String.replace("\r\n", "\n")
  end

  defp render_main(_state, _width, _height, opts), do: Theme.muted("No session.", opts)

  defp render_review(%{review: %CoreReview{} = review} = state, width, opts) do
    ReviewRenderer.render(
      review,
      open_file_path(Map.get(state, :open_file)),
      Map.get(state, :active_review_comment_id),
      width,
      opts
    )
  end

  defp render_review(_state, _width, opts), do: Theme.muted("No review.", opts)

  defp render_palette(%{palette: %CorePalette{open?: true} = palette}, width, opts) do
    PaletteRenderer.render(palette, width, opts)
  end

  defp render_palette(_state, _width, _opts), do: ""

  defp render_footer(state, width, opts) do
    state
    |> footer_actions()
    |> Enum.map_join(" · ", &footer_action/1)
    |> TextLayout.truncate(width)
    |> Theme.muted(opts)
  end

  defp footer_actions(%{palette: %CorePalette{open?: true}}) do
    [
      "tilde.palette.previous",
      "tilde.palette.next",
      "tilde.palette.accept",
      "tilde.palette.close"
    ]
  end

  defp footer_actions(%{workspace_mode: :file} = state) do
    [
      "tilde.palette.open",
      "tilde.workspace.view_files",
      "tilde.workspace.view_symbols",
      "tilde.review.focus",
      review_toggle_action(state),
      "tilde.session.chat"
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp footer_actions(%{workspace_mode: :workspace}) do
    [
      "tilde.palette.open",
      "tilde.workspace.focus_previous",
      "tilde.workspace.focus_next",
      "tilde.workspace.open_focused",
      "tilde.workspace.view_files",
      "tilde.workspace.view_symbols",
      "tilde.session.chat"
    ]
  end

  defp footer_actions(_state) do
    [
      "tilde.palette.open",
      "tilde.workspace.focus_previous",
      "tilde.workspace.focus_next",
      "tilde.workspace.open_focused",
      "tilde.workspace.view_files",
      "tilde.workspace.view_symbols"
    ]
  end

  defp review_toggle_action(state) do
    case active_review_comment(state) do
      %{status: :open} -> {"tilde.review.toggle_current", "resolve"}
      %{status: :resolved} -> {"tilde.review.toggle_current", "reopen"}
      _comment -> nil
    end
  end

  defp active_review_comment(%{review: %CoreReview{} = review, active_review_comment_id: id}) do
    id = id || CoreReview.focused_comment_id(review, nil)

    if is_binary(id) do
      CoreReview.find_comment(review, id)
    end
  end

  defp active_review_comment(_state), do: nil

  defp footer_action({id, label}), do: footer_key(id) <> " " <> label

  defp footer_action(id) when is_binary(id) do
    footer_key(id) <> " " <> (Shortcuts.label(id) || id)
  end

  defp footer_key(id), do: Shortcuts.display_key(id) || ""

  defp symbols(%{open_file: %FileBuffer{symbols: symbols}}), do: symbols
  defp symbols(_state), do: []

  defp open_file_path(%FileBuffer{path: path}), do: path
  defp open_file_path(_open_file), do: nil

  defp maybe_clip(body, height) when is_integer(height) and height > 0 do
    body
    |> String.split("\n")
    |> Enum.take(-height)
    |> Enum.join("\n")
  end

  defp maybe_clip(body, _height), do: body

  defp truncate(text, width) do
    if String.length(text) <= width do
      text
    else
      String.slice(text, 0, max(width - 1, 0)) <> "…"
    end
  end

  defp terminal_newlines(iodata) do
    iodata
    |> IO.iodata_to_binary()
    |> String.replace("\n", "\r\n")
  end
end
