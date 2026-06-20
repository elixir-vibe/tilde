defmodule Tilde.Tools.Write do
  @moduledoc "Model-facing file write tool."

  import JSONSpec

  alias Tilde.Tool.{File, Output}

  @schema schema(
            %{
              required(:path) => String.t(),
              required(:content) => String.t()
            },
            doc: [path: "Path to write", content: "File content"]
          )

  use Jido.Action,
    name: "write",
    description: "Write text content to a file, creating parent directories as needed.",
    category: "filesystem",
    tags: ["filesystem", "write"],
    schema: @schema

  @impl true
  def run(params, _context) do
    params = JSONSpec.atomize(@schema, params)

    with {:ok, result} <- File.write_text(params.path, params.content) do
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
end
