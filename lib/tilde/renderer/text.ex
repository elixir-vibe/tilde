defmodule Tilde.Renderer.Text do
  @moduledoc """
  Plain text renderer for transcripts.

  This is useful for tests, logs, snapshots, and a future ANSI renderer baseline.
  """

  @behaviour Tilde.Renderer

  alias Tilde.{Block, ToolView, Transcript}

  @impl true
  def render(%Transcript{} = transcript, _opts \\ []) do
    transcript.blocks
    |> Enum.map(&render_block/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp render_block(%Block{kind: :message, role: role, source: source}) do
    "#{role}\n#{indent(source)}"
  end

  defp render_block(%Block{kind: :tool} = block) do
    view = ToolView.view(block)
    status = Atom.to_string(view.status)

    header =
      [view.name, view.arg_summary, status] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")

    output = Enum.join(view.lines, "\n")
    hidden = hidden_footer(view)

    [header, output, hidden]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_block(%Block{kind: kind, source: source}), do: "#{kind}\n#{indent(source)}"

  defp hidden_footer(%{hidden_lines: 0}), do: ""

  defp hidden_footer(%{hidden_lines: count}) do
    "… #{count} more lines\n(ctrl+o to expand)"
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"  #{&1}")
  end
end
