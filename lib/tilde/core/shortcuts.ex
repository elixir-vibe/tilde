defmodule Tilde.Core.Shortcuts do
  @moduledoc """
  Central shortcut registry for semantic Tilde actions.

  This mirrors Pi's keybinding shape at Tilde's current scale: components refer
  to namespaced shortcut ids, renderers ask this registry for display keys, and
  keyboard input is resolved to semantic ids before LiveView/TUI handlers act.
  """

  alias Tilde.Core.Shortcut

  @definitions [
    Shortcut.new(
      id: "tilde.workspace.view_files",
      keys: "f",
      label: "files",
      description: "Show files in the workspace navigator",
      scopes: [:chat, :workspace, :buffer]
    ),
    Shortcut.new(
      id: "tilde.workspace.view_symbols",
      keys: "s",
      label: "symbols",
      description: "Show current-file symbols in the workspace navigator",
      scopes: [:chat, :workspace, :buffer]
    ),
    Shortcut.new(
      id: "tilde.session.chat",
      keys: "escape",
      label: "chat",
      description: "Return to chat",
      scopes: [:workspace, :buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.review.focus",
      keys: "r",
      label: "review",
      description: "Open the active review comment",
      scopes: [:buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.review.toggle_current",
      keys: "x",
      label: "resolve",
      description: "Resolve or reopen the active review comment",
      scopes: [:buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.review.next",
      keys: "n",
      label: "next",
      description: "Open the next review comment",
      scopes: [:buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.review.previous",
      keys: "p",
      label: "previous",
      description: "Open the previous review comment",
      scopes: [:buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.workspace.focus_previous",
      keys: ["arrowup", "k"],
      label: "previous",
      description: "Focus the previous workspace file",
      scopes: [:chat, :workspace, :buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.workspace.focus_next",
      keys: ["arrowdown", "j"],
      label: "next",
      description: "Focus the next workspace file",
      scopes: [:chat, :workspace, :buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.workspace.open_focused",
      keys: "enter",
      label: "open",
      description: "Open the focused workspace file",
      scopes: [:chat, :workspace, :buffer],
      prevent_default?: true
    ),
    Shortcut.new(
      id: "tilde.palette.open",
      keys: "ctrl+p",
      label: "palette",
      description: "Open the command palette",
      scopes: [:chat, :workspace, :buffer, :palette],
      prevent_default?: true,
      capture_interactive?: true
    ),
    Shortcut.new(
      id: "tilde.palette.mode_files",
      keys: "f",
      label: "files",
      description: "Switch the command palette to files",
      scopes: [:palette]
    ),
    Shortcut.new(
      id: "tilde.palette.mode_symbols",
      keys: "s",
      label: "symbols",
      description: "Switch the command palette to symbols",
      scopes: [:palette]
    ),
    Shortcut.new(
      id: "tilde.palette.close",
      keys: "escape",
      label: "close",
      description: "Close the command palette",
      scopes: [:palette],
      prevent_default?: true,
      capture_interactive?: true
    ),
    Shortcut.new(
      id: "tilde.palette.previous",
      keys: "arrowup",
      label: "previous",
      description: "Select the previous palette item",
      scopes: [:palette],
      prevent_default?: true,
      capture_interactive?: true
    ),
    Shortcut.new(
      id: "tilde.palette.next",
      keys: "arrowdown",
      label: "next",
      description: "Select the next palette item",
      scopes: [:palette],
      prevent_default?: true,
      capture_interactive?: true
    ),
    Shortcut.new(
      id: "tilde.palette.accept",
      keys: "enter",
      label: "open",
      description: "Open the selected palette item",
      scopes: [:palette],
      prevent_default?: true,
      capture_interactive?: true
    )
  ]

  @by_id Map.new(@definitions, &{&1.id, &1})

  @doc "Returns all shortcut definitions."
  @spec all() :: [Shortcut.t()]
  def all, do: @definitions

  @doc "Fetches a shortcut definition by id."
  @spec get(String.t()) :: Shortcut.t() | nil
  def get(id) when is_binary(id), do: Map.get(@by_id, id)

  @doc "Returns the display label for a shortcut id."
  @spec label(String.t() | nil) :: String.t() | nil
  def label(nil), do: nil

  def label(id) when is_binary(id) do
    case get(id) do
      %Shortcut{label: label} when label != "" -> label
      _shortcut -> nil
    end
  end

  @doc "Returns the first display key for a shortcut id."
  @spec display_key(String.t() | nil) :: String.t() | nil
  def display_key(nil), do: nil

  def display_key(id) when is_binary(id) do
    case get(id) do
      %Shortcut{keys: [key | _]} -> key
      _shortcut -> nil
    end
  end

  @doc "Returns browser-facing shortcut metadata."
  @spec browser_bindings() :: [map()]
  def browser_bindings do
    Enum.map(@definitions, fn %Shortcut{} = shortcut ->
      %{
        "id" => shortcut.id,
        "keys" => Enum.map(shortcut.keys, &normalize_key/1),
        "scopes" => Enum.map(shortcut.scopes, &Atom.to_string/1),
        "preventDefault" => shortcut.prevent_default?,
        "captureInteractive" => shortcut.capture_interactive?
      }
    end)
  end

  @doc "Resolves a normalized key in a scope to a shortcut id."
  @spec match(Shortcut.scope(), String.t()) :: String.t() | nil
  def match(scope, key) when is_atom(scope) and is_binary(key) do
    normalized = normalize_key(key)

    @definitions
    |> Enum.find(fn %Shortcut{keys: keys, scopes: scopes} ->
      scope in scopes and normalized in Enum.map(keys, &normalize_key/1)
    end)
    |> case do
      %Shortcut{id: id} -> id
      nil -> nil
    end
  end

  defp normalize_key(key) when is_binary(key), do: String.downcase(key)
end
