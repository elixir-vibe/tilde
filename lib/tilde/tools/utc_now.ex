defmodule Tilde.Tools.UtcNow do
  @moduledoc """
  Safe demo Jido tool that returns the current UTC time.
  """

  if Code.ensure_loaded?(Jido.Action) do
    use Jido.Action,
      name: "utc_now",
      description: "Returns the current UTC time in ISO 8601 format.",
      category: "time",
      tags: ["time", "demo"],
      schema: [],
      output_schema: [utc_now: [type: :string, required: true]]

    @impl true
    def run(_params, _context) do
      {:ok, %{utc_now: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}}
    end
  end
end
