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
  def result(%Block{} = block, opts \\ []), do: Viewer.Default.result(block, opts)

  defp tags(block) do
    shell = Viewer.Default.fetch_key(block.args, :shell)
    if shell in [nil, "", "bash"], do: [], else: [to_string(shell)]
  end
end
