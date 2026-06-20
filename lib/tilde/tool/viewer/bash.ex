defmodule Tilde.Tool.Viewer.Bash do
  @moduledoc """
  Semantic renderer for shell command tool calls.
  """

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    command = Viewer.Default.fetch_key(block.args, :command)

    Tilde.Tool.View.call(block.name || "bash",
      segments: if(command in [nil, ""], do: [], else: [%{text: command, color: :accent}]),
      tags: tags(block),
      suffix: Viewer.Default.fetch_key(block.metadata, :suffix)
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    default = Viewer.Default.result(block, opts)
    lines = Viewer.Default.result_content_lines(block.result)

    if default.lines == [] and default.streams == [] and lines != [] do
      expanded? = Keyword.get(opts, :expanded?, false)
      line_limit = Keyword.get(opts, :line_limit, 8)
      visible = if expanded?, do: lines, else: Enum.take(lines, -line_limit)

      %{
        default
        | lines: visible,
          hidden_lines: if(expanded?, do: 0, else: max(length(lines) - length(visible), 0))
      }
    else
      default
    end
  end

  defp tags(block) do
    shell = Viewer.Default.fetch_key(block.args, :shell)
    if shell in [nil, "", "bash"], do: [], else: [to_string(shell)]
  end
end
