defmodule Tilde.View.Cell do
  @moduledoc """
  Shared semantic view cell used by LiveView and TUI renderers.

  Cells describe visual intent such as kind, state, padding, text lines, actions,
  and source content without committing to HTML, ANSI, or a terminal grid.
  """

  alias Tilde.Core.Run
  alias Tilde.View.Line

  defstruct id: nil,
            kind: :block,
            state: :normal,
            role: nil,
            format: :plain,
            source: "",
            runs: [],
            lines: [],
            actions: [],
            attrs: %{},
            padding_x: 1,
            padding_y: 1

  @type state :: :normal | :pending | :success | :error | :cancelled
  @type line :: String.t() | Line.t() | :blank | [Run.t()]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: atom(),
          state: state(),
          role: atom() | nil,
          format: atom(),
          source: String.t(),
          runs: [Run.t()],
          lines: [line()],
          actions: [term()],
          attrs: map(),
          padding_x: non_neg_integer(),
          padding_y: non_neg_integer()
        }

  @doc "Creates a view cell."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      kind: Keyword.get(opts, :kind, :block),
      state: Keyword.get(opts, :state, :normal),
      role: Keyword.get(opts, :role),
      format: Keyword.get(opts, :format, :plain),
      source: Keyword.get(opts, :source, ""),
      runs: Keyword.get(opts, :runs, []),
      lines: Keyword.get(opts, :lines, []),
      actions: Keyword.get(opts, :actions, []),
      attrs: Keyword.get(opts, :attrs, %{}),
      padding_x: Keyword.get(opts, :padding_x, 1),
      padding_y: Keyword.get(opts, :padding_y, 1)
    }
  end
end
