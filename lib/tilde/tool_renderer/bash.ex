defmodule Tilde.ToolRenderer.Bash do
  @moduledoc """
  Semantic renderer for shell command tool calls.
  """

  @behaviour Tilde.ToolRenderer

  alias Tilde.{Block, ToolRenderer}

  @impl true
  def call(%Block{} = block) do
    command = ToolRenderer.Default.fetch_key(block.args, :command)

    ToolRenderer.call_view(block.name || "bash",
      segments: if(command in [nil, ""], do: [], else: [%{text: command, color: :accent}]),
      tags: tags(block),
      suffix: ToolRenderer.Default.fetch_key(block.metadata, :suffix)
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []), do: ToolRenderer.Default.result(block, opts)

  defp tags(block) do
    shell = ToolRenderer.Default.fetch_key(block.args, :shell)
    if shell in [nil, "", "bash"], do: [], else: [to_string(shell)]
  end
end
