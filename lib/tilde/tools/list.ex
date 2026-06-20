defmodule Tilde.Tools.List do
  @moduledoc "Model-facing directory listing tool."

  import JSONSpec

  alias Tilde.Tool.{File, Output}

  @schema schema(
            %{
              required(:path) => String.t(),
              optional(:all) => boolean(),
              optional(:limit) => pos_integer()
            },
            doc: [
              path: "Path to the directory to list, relative or absolute",
              all: "Include hidden entries whose names start with a dot",
              limit: "Maximum number of entries to return"
            ]
          )

  use Jido.Action,
    name: "list",
    description:
      "List entries in a directory. Use this before read when exploring folders; read only accepts regular text files.",
    category: "filesystem",
    tags: ["filesystem", "directory", "list"],
    schema: @schema

  @impl true
  def run(params, _context) do
    params = JSONSpec.atomize(@schema, params)

    with {:ok, result} <-
           File.list_directory(params.path, all: params[:all], limit: params[:limit]) do
      text = render_listing(result)
      {content, truncation} = Output.truncate_head(text)

      {:ok,
       %{
         content: [Output.text_part(content)],
         details: %{truncation: truncation},
         path: result.path,
         entries: result.entries,
         total_entries: result.total_entries,
         selected_entries: result.selected_entries
       }}
    end
  end

  defp render_listing(%{
         path: path,
         entries: entries,
         total_entries: total,
         selected_entries: selected
       }) do
    header = "#{path}/ (#{selected} of #{total} entries)"
    lines = Enum.map(entries, &render_entry/1)
    Enum.join([header | lines], "\n")
  end

  defp render_entry(%{name: name, type: :directory}), do: "#{name}/"
  defp render_entry(%{name: name, type: type, size: size}), do: "#{name}\t#{type}\t#{size} bytes"
  defp render_entry(%{name: name, type: type}), do: "#{name}\t#{type}"
end
