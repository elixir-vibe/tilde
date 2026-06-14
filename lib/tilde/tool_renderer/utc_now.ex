defmodule Tilde.ToolRenderer.UtcNow do
  @moduledoc """
  Semantic renderer for the safe demo UTC time tool.
  """

  @behaviour Tilde.ToolRenderer

  alias Tilde.{Block, ToolRenderer}

  @impl true
  def call(%Block{} = block) do
    ToolRenderer.call_view(block.name || "utc_now", tags: ["time"])
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    view = ToolRenderer.Default.result(block, opts)

    case utc_now(block.result) do
      nil ->
        view

      timestamp ->
        %{
          view
          | streams: [%{id: "result", kind: :result, lines: [timestamp], hidden_lines: 0}],
            lines: [timestamp],
            waiting?: false
        }
    end
  end

  defp utc_now(result) when is_map(result) do
    ToolRenderer.Default.fetch_key(result, :utc_now)
  end

  defp utc_now(_result), do: nil
end
