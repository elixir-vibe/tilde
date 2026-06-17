defmodule Tilde.Core.Widget do
  @moduledoc """
  Semantic widget mounted outside the historical transcript.

  Widgets model pi-like regions such as content above the input editor, below the
  editor, footer/statusline content, overlays, and sidecars. They are ephemeral
  UI state, not transcript history, unless an application also emits events for
  them.
  """

  alias Tilde.Core.Action

  @type placement :: :above_input | :below_input | :footer | :overlay | :sidecar

  @type t :: %__MODULE__{
          id: String.t(),
          placement: placement(),
          kind: atom(),
          content: term(),
          actions: [Action.t()],
          metadata: map(),
          children: [t()]
        }

  defstruct id: nil,
            placement: :above_input,
            kind: :content,
            content: nil,
            actions: [],
            metadata: %{},
            children: []

  @doc "Creates a widget."
  @spec new(String.t(), placement(), term(), keyword()) :: t()
  def new(id, placement, content, opts \\ []) when is_binary(id) do
    %__MODULE__{
      id: id,
      placement: placement,
      kind: Keyword.get(opts, :kind, :content),
      content: content,
      actions: Keyword.get(opts, :actions, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      children: Keyword.get(opts, :children, [])
    }
  end

  @doc "Creates a semantic screen widget."
  @spec screen(String.t(), [t()], keyword()) :: t()
  def screen(id, children, opts \\ []) when is_binary(id) and is_list(children) do
    new(id, Keyword.get(opts, :placement, :overlay), Keyword.get(opts, :content),
      kind: :screen,
      children: children,
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  @doc "Creates a semantic section widget."
  @spec section(String.t(), String.t(), [t()], keyword()) :: t()
  def section(id, title, children, opts \\ []) when is_binary(id) and is_binary(title) do
    new(id, Keyword.get(opts, :placement, :above_input), title,
      kind: :section,
      children: children,
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  @doc "Creates a semantic text widget."
  @spec text(String.t(), String.t(), keyword()) :: t()
  def text(id, text, opts \\ []) when is_binary(id) and is_binary(text) do
    new(id, Keyword.get(opts, :placement, :above_input), text,
      kind: Keyword.get(opts, :kind, :text),
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  @doc "Creates a semantic input widget."
  @spec input(String.t(), Tilde.Core.Input.t(), keyword()) :: t()
  def input(id, input, opts \\ []) when is_binary(id) do
    new(id, Keyword.get(opts, :placement, :below_input), input, kind: :input)
  end

  @doc "Creates a semantic shortcut bar widget."
  @spec shortcut_bar(String.t(), [map()], keyword()) :: t()
  def shortcut_bar(id, shortcuts, opts \\ []) when is_binary(id) and is_list(shortcuts) do
    new(id, Keyword.get(opts, :placement, :below_input), shortcuts, kind: :shortcut_bar)
  end

  @doc "Creates a semantic footer widget."
  @spec footer(String.t(), keyword()) :: t()
  def footer(id, opts \\ []) when is_binary(id) do
    content = %{left: Keyword.get(opts, :left, ""), right: Keyword.get(opts, :right, "")}
    new(id, Keyword.get(opts, :placement, :footer), content, kind: :footer)
  end
end
