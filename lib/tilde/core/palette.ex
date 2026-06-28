defmodule Tilde.Core.Palette do
  @moduledoc """
  Renderer-neutral command palette state.

  The palette has explicit modes instead of mixing unrelated item types into one
  flat list. File mode opens relevant workspace files. Symbol mode jumps within
  the currently open file buffer.
  """

  alias Tilde.Core.FileBuffer
  alias Tilde.Core.FileSymbol
  alias Tilde.Core.Palette.Item
  alias Tilde.Core.Workspace

  defstruct open?: false, mode: :files, query: "", selected_index: 0, items: []

  @type mode :: :files | :symbols

  @type t :: %__MODULE__{
          open?: boolean(),
          mode: mode(),
          query: String.t(),
          selected_index: non_neg_integer(),
          items: [Item.t()]
        }

  @doc "Builds palette state."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    items = Keyword.get(opts, :items, [])

    %__MODULE__{
      open?: Keyword.get(opts, :open?, false),
      mode: normalize_mode(Keyword.get(opts, :mode, :files)),
      query: Keyword.get(opts, :query, ""),
      selected_index: clamp_index(Keyword.get(opts, :selected_index, 0), items),
      items: items
    }
  end

  @doc "Builds an open file palette from relevant workspace files."
  @spec open_files(Workspace.t(), String.t()) :: t()
  def open_files(%Workspace{} = workspace, query \\ "") do
    build(:files, file_items(workspace), query, open?: true)
  end

  @doc "Builds an open symbol palette from the current file buffer."
  @spec open_symbols(FileBuffer.t() | nil, String.t()) :: t()
  def open_symbols(open_file, query \\ "") do
    build(:symbols, symbol_items(open_file), query, open?: true)
  end

  @doc "Updates the query and filtered item list for a file palette."
  @spec query_files(t(), Workspace.t(), String.t()) :: t()
  def query_files(%__MODULE__{} = palette, %Workspace{} = workspace, query)
      when is_binary(query) do
    update_items(palette, :files, file_items(workspace), query)
  end

  @doc "Updates the query and filtered item list for a symbol palette."
  @spec query_symbols(t(), FileBuffer.t() | nil, String.t()) :: t()
  def query_symbols(%__MODULE__{} = palette, open_file, query) when is_binary(query) do
    update_items(palette, :symbols, symbol_items(open_file), query)
  end

  @doc "Updates the query for whichever mode the palette is currently using."
  @spec query(t(), Workspace.t(), FileBuffer.t() | nil, String.t()) :: t()
  def query(%__MODULE__{mode: :symbols} = palette, _workspace, open_file, query) do
    query_symbols(palette, open_file, query)
  end

  def query(%__MODULE__{} = palette, %Workspace{} = workspace, _open_file, query) do
    query_files(palette, workspace, query)
  end

  @doc "Refreshes palette items against current workspace/file context."
  @spec refresh(t() | term(), Workspace.t(), FileBuffer.t() | nil) :: t()
  def refresh(
        %__MODULE__{open?: true, query: query} = palette,
        %Workspace{} = workspace,
        open_file
      ) do
    %{query(palette, workspace, open_file, query) | open?: true}
  end

  def refresh(%__MODULE__{} = palette, _workspace, _open_file), do: palette
  def refresh(_palette, _workspace, _open_file), do: new()

  @doc "Switches palette mode and rebuilds items with the current query."
  @spec switch_mode(t(), mode() | String.t(), Workspace.t(), FileBuffer.t() | nil) :: t()
  def switch_mode(%__MODULE__{} = palette, mode, %Workspace{} = workspace, open_file) do
    mode = normalize_mode(mode)

    case mode do
      :symbols -> query_symbols(%{palette | mode: :symbols}, open_file, palette.query)
      :files -> query_files(%{palette | mode: :files}, workspace, palette.query)
    end
  end

  @doc "Moves selected item up or down, wrapping across visible items."
  @spec move(t(), :previous | :next) :: t()
  def move(%__MODULE__{items: []} = palette, _direction), do: palette

  def move(%__MODULE__{} = palette, direction) do
    step = if direction == :previous, do: -1, else: 1
    count = length(palette.items)
    %{palette | selected_index: Integer.mod(palette.selected_index + step, count)}
  end

  @doc "Returns the currently selected visible item."
  @spec selected_item(t()) :: Item.t() | nil
  def selected_item(%__MODULE__{items: items, selected_index: index}), do: Enum.at(items, index)

  defp build(mode, all_items, query, opts) do
    items = filter_items(all_items, query)
    new(open?: Keyword.get(opts, :open?, false), mode: mode, query: query, items: items)
  end

  defp update_items(%__MODULE__{} = palette, mode, all_items, query) do
    items = filter_items(all_items, query)
    %{palette | mode: mode, query: query, selected_index: clamp_index(0, items), items: items}
  end

  defp file_items(%Workspace{} = workspace) do
    workspace
    |> Workspace.file_sections()
    |> Enum.flat_map(&tree_file_items(&1.tree))
  end

  defp tree_file_items(nodes) do
    Enum.flat_map(nodes, fn
      %{kind: :file, file: %{path: path}} -> [file_item(path)]
      %{children: children} -> tree_file_items(children)
    end)
  end

  defp file_item(path) do
    Item.new(
      id: "file:#{path}",
      label: Path.basename(path),
      detail: path,
      kind: :file,
      action: %{type: :open_file, path: path}
    )
  end

  defp symbol_items(%FileBuffer{path: path, symbols: symbols}) do
    Enum.map(symbols, &symbol_item(path, &1))
  end

  defp symbol_items(_open_file), do: []

  defp symbol_item(path, %FileSymbol{} = symbol) do
    Item.new(
      id: "symbol:#{path}:#{symbol.line}:#{symbol.name}",
      label: symbol.name,
      detail: symbol_detail(symbol),
      kind: :symbol,
      action: %{type: :jump_symbol, path: path, line: symbol.line}
    )
  end

  defp symbol_detail(%FileSymbol{} = symbol),
    do: "#{symbol.kind} · line #{symbol.line}"

  defp filter_items(items, query) do
    terms = query_terms(query)

    items
    |> Enum.filter(&matches?(&1, terms))
    |> Enum.sort_by(&score(&1, terms))
  end

  defp query_terms(query) do
    query
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
  end

  defp matches?(_item, []), do: true

  defp matches?(%Item{} = item, terms) do
    haystack = String.downcase(Enum.join([item.label, item.detail || ""], " "))
    Enum.all?(terms, &String.contains?(haystack, &1))
  end

  defp score(%Item{} = item, []) do
    {0, item.detail || item.label}
  end

  defp score(%Item{} = item, [first | _terms]) do
    label = String.downcase(item.label)
    detail = String.downcase(item.detail || item.label)

    basename_rank = if String.contains?(label, first), do: 0, else: 1
    position = :binary.match(detail, first) |> match_position()

    {basename_rank, position, String.length(detail), detail}
  end

  defp match_position({position, _length}), do: position
  defp match_position(:nomatch), do: 100_000

  defp normalize_mode("symbols"), do: :symbols
  defp normalize_mode(:symbols), do: :symbols
  defp normalize_mode(_mode), do: :files

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, items), do: min(max(index, 0), length(items) - 1)
end
