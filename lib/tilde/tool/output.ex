defmodule Tilde.Tool.Output do
  @moduledoc "Context-safe limits for model-facing tool output."

  @default_max_bytes 50 * 1_024
  @default_max_lines 2_000

  @type truncation :: %{
          truncated: boolean(),
          truncatedBy: String.t() | nil,
          outputLines: non_neg_integer(),
          totalLines: non_neg_integer(),
          maxLines: pos_integer(),
          maxBytes: pos_integer()
        }

  @spec default_max_bytes() :: pos_integer()
  def default_max_bytes, do: @default_max_bytes

  @spec default_max_lines() :: pos_integer()
  def default_max_lines, do: @default_max_lines

  @spec text_part(String.t()) :: %{type: String.t(), text: String.t()}
  def text_part(text) when is_binary(text), do: %{type: "text", text: text}

  @doc "Limits text from the head, matching read-like document output."
  @spec truncate_head(String.t(), keyword()) :: {String.t(), truncation() | nil}
  def truncate_head(text, opts \\ []) when is_binary(text) do
    truncate(text, opts, :head)
  end

  @doc "Limits text from the tail, matching append-only command output."
  @spec truncate_tail(String.t(), keyword()) :: {String.t(), truncation() | nil}
  def truncate_tail(text, opts \\ []) when is_binary(text) do
    truncate(text, opts, :tail)
  end

  defp truncate(text, opts, direction) do
    max_lines = Keyword.get(opts, :max_lines, @default_max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    lines = String.split(text, "\n", trim: false)
    total_lines = length(lines)

    {byte_limited, byte_truncated?} = limit_bytes(text, max_bytes, direction)
    byte_lines = String.split(byte_limited, "\n", trim: false)

    {limited_lines, line_truncated?} = limit_lines(byte_lines, max_lines, direction)
    output = Enum.join(limited_lines, "\n")

    truncation =
      if byte_truncated? or line_truncated? do
        %{
          truncated: true,
          truncatedBy: if(line_truncated?, do: "lines", else: "bytes"),
          outputLines: length(limited_lines),
          totalLines: total_lines,
          maxLines: max_lines,
          maxBytes: max_bytes
        }
      end

    {output, truncation}
  end

  defp limit_bytes(text, max_bytes, _direction) when byte_size(text) <= max_bytes,
    do: {text, false}

  defp limit_bytes(text, max_bytes, :head) do
    {binary_part(text, 0, max_bytes) |> valid_prefix(), true}
  end

  defp limit_bytes(text, max_bytes, :tail) do
    offset = byte_size(text) - max_bytes
    {binary_part(text, offset, max_bytes) |> valid_suffix(), true}
  end

  defp limit_lines(lines, max_lines, _direction) when length(lines) <= max_lines,
    do: {lines, false}

  defp limit_lines(lines, max_lines, :head), do: {Enum.take(lines, max_lines), true}
  defp limit_lines(lines, max_lines, :tail), do: {Enum.take(lines, -max_lines), true}

  defp valid_prefix(text) do
    if String.valid?(text),
      do: text,
      else: text |> binary_part(0, byte_size(text) - 1) |> valid_prefix()
  end

  defp valid_suffix(text) do
    if String.valid?(text),
      do: text,
      else: text |> binary_part(1, byte_size(text) - 1) |> valid_suffix()
  end
end
