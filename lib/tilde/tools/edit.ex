defmodule Tilde.Tools.Edit do
  @moduledoc "Model-facing exact replacement edit tool."

  import JSONSpec

  alias Tilde.Tool.{File, Output}

  @schema schema(
            %{
              required(:path) => String.t(),
              required(:edits) => [
                %{
                  required(:oldText) => String.t(),
                  required(:newText) => String.t()
                }
              ]
            },
            doc: [
              path: "Path to the file to edit",
              edits:
                "Exact text replacements. Each oldText must uniquely match the original file; replacements are applied together."
            ]
          )

  use Jido.Action,
    name: "edit",
    description:
      "Edit a text file using exact replacements. Every edits[].oldText must match a unique, non-overlapping region of the original file.",
    category: "filesystem",
    tags: ["filesystem", "edit"],
    schema: @schema

  @impl true
  def run(params, _context) do
    params = JSONSpec.atomize(@schema, maybe_decode_edits(params))

    with {:ok, result} <- File.edit_text(params.path, params.edits) do
      {:ok,
       %{
         content: [Output.text_part(result.message)],
         details: %{
           diff: result.diff,
           patch: result.patch,
           firstChangedLine: result.firstChangedLine
         },
         diff: result.diff,
         patch: result.patch,
         firstChangedLine: result.firstChangedLine
       }}
    end
  end

  defp maybe_decode_edits(%{"edits" => edits} = params) when is_binary(edits) do
    case Jason.decode(edits) do
      {:ok, decoded} when is_list(decoded) -> %{params | "edits" => decoded}
      _other -> params
    end
  end

  defp maybe_decode_edits(%{edits: edits} = params) when is_binary(edits) do
    case Jason.decode(edits) do
      {:ok, decoded} when is_list(decoded) -> %{params | edits: decoded}
      _other -> params
    end
  end

  defp maybe_decode_edits(params), do: params
end
