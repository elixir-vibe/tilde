defmodule Tilde.Tool.View.Stream do
  @moduledoc "Renderer-neutral semantic tool stream view."

  alias Tilde.Core.Stream, as: CoreStream

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          lines: [String.t()],
          hidden_lines: non_neg_integer(),
          byte_count: non_neg_integer(),
          line_count: non_neg_integer()
        }

  defstruct id: nil, kind: :stdout, lines: [], hidden_lines: 0, byte_count: 0, line_count: 0

  @doc "Builds compact stream views using the requested visible-line direction."
  @spec views([CoreStream.t()], :all | non_neg_integer(), :head | :tail) :: [t()]
  def views(streams, :all, _direction) do
    Enum.map(streams, fn stream ->
      lines = CoreStream.lines(stream)
      from_stream(stream, lines)
    end)
  end

  def views(streams, limit, direction) when is_integer(limit) do
    {views, _remaining} =
      Enum.map_reduce(streams, limit, fn stream, remaining ->
        lines = CoreStream.lines(stream)
        visible = take(lines, max(remaining, 0), direction)
        {from_stream(stream, visible), max(remaining - length(visible), 0)}
      end)

    views
  end

  defp from_stream(%CoreStream{} = stream, visible_lines) do
    lines = CoreStream.lines(stream)

    %__MODULE__{
      id: stream.id,
      kind: stream.kind,
      lines: visible_lines,
      hidden_lines: max(length(lines) - length(visible_lines), 0),
      byte_count: CoreStream.byte_count(stream),
      line_count: length(lines)
    }
  end

  defp take(_lines, limit, _direction) when limit <= 0, do: []
  defp take(lines, limit, :head), do: Enum.take(lines, limit)
  defp take(lines, limit, :tail), do: Enum.take(lines, -limit)
end
