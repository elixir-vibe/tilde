defmodule Tilde.Tool.Viewer.List do
  @moduledoc "Semantic renderer for directory listing tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    path = Viewer.Default.fetch_key(block.args, :path)

    Tilde.Tool.View.call("list",
      segments: if(path in [nil, ""], do: [], else: [%{text: path, color: :accent}])
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    default = Viewer.Default.result(block, opts)
    lines = Viewer.Default.result_content_lines(block.result)

    if default.lines == [] and default.streams == [] and lines != [] do
      expanded? = Keyword.get(opts, :expanded?, false)
      line_limit = Keyword.get(opts, :line_limit, 8)
      visible = if expanded?, do: lines, else: Enum.take(lines, line_limit)

      %{
        default
        | lines: visible,
          hidden_lines: if(expanded?, do: 0, else: max(length(lines) - length(visible), 0))
      }
    else
      default
    end
  end
end
