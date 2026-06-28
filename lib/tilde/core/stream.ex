defmodule Tilde.Core.Stream do
  @moduledoc """
  Append-only stream inside a tool block.

  A stream keeps chunks losslessly while exposing derived line and byte counts for
  compact renderers.
  """

  @type kind :: :stdout | :stderr | :log | :result

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          chunks: [String.t()],
          complete?: boolean()
        }

  defstruct id: nil, kind: :stdout, chunks: [], complete?: false

  @doc "Creates an empty stream."
  @spec new(kind(), keyword()) :: t()
  def new(kind, opts \\ []) do
    id = Keyword.get(opts, :id, Atom.to_string(kind))
    %__MODULE__{id: id, kind: kind, chunks: Keyword.get(opts, :chunks, [])}
  end

  @doc "Appends a chunk to the stream."
  @spec append(t(), String.t()) :: t()
  def append(%__MODULE__{} = stream, chunk) when is_binary(chunk) do
    %{stream | chunks: [chunk | stream.chunks]}
  end

  @doc "Returns stream chunks in chronological order."
  @spec chunks(t()) :: [String.t()]
  def chunks(%__MODULE__{chunks: chunks}), do: Enum.reverse(chunks)

  @doc "Returns newly appended chronological chunk text when old is a prefix of new."
  @spec appended_text(t(), t()) :: {String.t(), boolean()} | nil
  def appended_text(%__MODULE__{} = old, %__MODULE__{} = new) do
    with true <- suffix?(new.chunks, old.chunks),
         added_count when added_count > 0 <- length(new.chunks) - length(old.chunks) do
      added = new.chunks |> Enum.take(added_count) |> Enum.reverse()
      {IO.iodata_to_binary(added), old.chunks == []}
    else
      _other -> nil
    end
  end

  @doc "Returns the full stream text."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = stream), do: stream |> chunks() |> IO.iodata_to_binary()

  @doc "Returns stream lines, preserving partial trailing lines."
  @spec lines(t()) :: [String.t()]
  def lines(%__MODULE__{} = stream) do
    stream
    |> text()
    |> String.split("\n")
    |> drop_final_empty_line()
  end

  @doc "Returns the number of output lines."
  @spec line_count(t()) :: non_neg_integer()
  def line_count(%__MODULE__{} = stream), do: stream |> lines() |> length()

  @doc "Returns the byte size of all chunks."
  @spec byte_count(t()) :: non_neg_integer()
  def byte_count(%__MODULE__{} = stream), do: stream |> text() |> byte_size()

  defp suffix?(list, suffix) do
    suffix_length = length(suffix)
    length(list) >= suffix_length and Enum.drop(list, length(list) - suffix_length) == suffix
  end

  defp drop_final_empty_line([]), do: []
  defp drop_final_empty_line([""]), do: []

  defp drop_final_empty_line(lines) do
    if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
  end
end
