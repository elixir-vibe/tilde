defmodule Tilde.Tools.Read do
  @moduledoc "Model-facing file read tool."

  import JSONSpec

  alias Tilde.Tool.{File, Output}

  @schema schema(
            %{
              required(:path) => String.t(),
              optional(:offset) => pos_integer(),
              optional(:limit) => pos_integer()
            },
            doc: [
              path: "Path to the file to read, relative or absolute",
              offset: "Line number to start reading from, 1-indexed",
              limit: "Maximum number of lines to read"
            ]
          )

  use Jido.Action,
    name: "read",
    description:
      "Read the contents of a text file. Output is truncated to 2000 lines or 50KB. Use offset/limit for large files.",
    category: "filesystem",
    tags: ["filesystem", "read"],
    schema: @schema

  @impl true
  def run(params, _context) do
    params = JSONSpec.atomize(@schema, params)

    with {:ok, result} <-
           File.read_text(params.path, offset: params[:offset], limit: params[:limit]) do
      {content, truncation} = Output.truncate_head(result.content)
      content = append_continuation_notice(content, result, params, truncation)

      {:ok,
       %{
         content: [Output.text_part(content)],
         details: %{truncation: truncation},
         path: result.path,
         lines: result.total_lines
       }}
    end
  end

  defp append_continuation_notice(content, result, params, truncation) do
    start_line = params.offset || 1
    shown_lines = content_lines(content)
    next_offset = start_line + shown_lines
    user_limited? = is_integer(params[:limit]) and next_offset <= result.total_lines
    truncated? = is_map(truncation) and truncation.truncated

    cond do
      truncated? ->
        "#{content}\n\n[Showing lines #{start_line}-#{next_offset - 1} of #{result.total_lines}. Use offset=#{next_offset} to continue.]"

      user_limited? ->
        remaining = result.total_lines - next_offset + 1
        "#{content}\n\n[#{remaining} more lines in file. Use offset=#{next_offset} to continue.]"

      true ->
        content
    end
  end

  defp content_lines(""), do: 0
  defp content_lines(text), do: text |> String.split("\n") |> length()
end
