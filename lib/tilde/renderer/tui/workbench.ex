defmodule Tilde.Renderer.TUI.Workbench do
  @moduledoc "Terminal renderer for the session workbench chrome."

  alias Tilde.Core.FileBuffer
  alias Tilde.Core.Palette, as: CorePalette
  alias Tilde.Core.Review, as: CoreReview
  alias Tilde.Core.Session
  alias Tilde.Core.Workspace, as: CoreWorkspace
  alias Tilde.Renderer.TUI
  alias Tilde.Renderer.TUI.Palette, as: PaletteRenderer
  alias Tilde.Renderer.TUI.Review, as: ReviewRenderer
  alias Tilde.Renderer.TUI.Theme
  alias Tilde.Renderer.TUI.Workspace, as: WorkspaceRenderer
  alias Tilde.Renderer.TUI.WorkspaceFile

  @type mode :: :chat | :file | :workspace
  @type view :: :files | :symbols

  @doc "Renders workspace, main surface, review, and optional palette."
  @spec render(map(), pos_integer(), pos_integer(), keyword()) :: iodata()
  def render(state, width, height, opts \\ []) when is_map(state) do
    ansi? = Keyword.get(opts, :ansi, true)
    opts = Keyword.put(opts, :ansi, ansi?)

    body =
      [
        Theme.title("# tilde", opts),
        section("workspace", render_workspace(state, width, opts), opts),
        section("main", render_main(state, width, height, opts), opts),
        section("review", render_review(state, width, opts), opts),
        render_palette(state, width, opts)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")
      |> maybe_clip(height)

    if ansi? do
      [IO.ANSI.home(), IO.ANSI.clear(), terminal_newlines(body)]
    else
      [body, "\n"]
    end
  end

  defp section(title, body, opts) do
    [Theme.muted("── #{title} ──", opts), body]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

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
