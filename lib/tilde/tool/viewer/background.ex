defmodule Tilde.Tool.Viewer.Background do
  @moduledoc "Semantic renderer for background process tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{name: "background-start"} = block) do
    name = Viewer.Default.fetch_key(block.args, :name)
    command = Viewer.Default.fetch_key(block.args, :command)

    Tilde.Tool.View.call("bg start",
      segments: [segment(name), command_segment(command)] |> Enum.reject(&is_nil/1)
    )
  end

  def call(%Block{name: "background-stop"} = block) do
    Tilde.Tool.View.call("bg stop",
      segments: [segment(Viewer.Default.fetch_key(block.args, :name))] |> Enum.reject(&is_nil/1)
    )
  end

  def call(%Block{name: "background-list"}) do
    Tilde.Tool.View.call("bg list")
  end

  def call(%Block{name: "background-logs"} = block) do
    lines = Viewer.Default.fetch_key(block.args, :lines)

    Tilde.Tool.View.call("bg logs",
      segments: [segment(Viewer.Default.fetch_key(block.args, :name))] |> Enum.reject(&is_nil/1),
      suffix: if(lines in [nil, ""], do: nil, else: "last #{lines}")
    )
  end

  def call(%Block{} = block), do: Viewer.Default.call(block)

  @impl true
  def result(%Block{} = block, opts \\ []), do: Viewer.Default.result(block, opts)

  defp segment(value) when value in [nil, ""], do: nil
  defp segment(value), do: %{text: value, color: :accent}

  defp command_segment(value) when value in [nil, ""], do: nil
  defp command_segment(value), do: %{text: "→ #{value}", color: :dim}
end
