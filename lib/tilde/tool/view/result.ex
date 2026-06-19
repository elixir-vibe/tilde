defmodule Tilde.Tool.View.Result do
  @moduledoc "Renderer-neutral semantic tool result view."

  alias Tilde.Tool.View.{ResultEntry, Stream}

  @type t :: %__MODULE__{
          metadata_rows: [{atom(), String.t()}],
          entries: [ResultEntry.t()],
          lines: [String.t()],
          streams: [Stream.t()],
          hidden_lines: non_neg_integer(),
          hidden_unit: String.t(),
          waiting?: boolean()
        }

  defstruct metadata_rows: [],
            entries: [],
            lines: [],
            streams: [],
            hidden_lines: 0,
            hidden_unit: "more lines",
            waiting?: false

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      metadata_rows: Keyword.get(opts, :metadata_rows, []),
      entries: Enum.map(Keyword.get(opts, :entries, []), &entry/1),
      lines: Keyword.get(opts, :lines, []),
      streams: Keyword.get(opts, :streams, []),
      hidden_lines: Keyword.get(opts, :hidden_lines, 0),
      hidden_unit: Keyword.get(opts, :hidden_unit, "more lines"),
      waiting?: Keyword.get(opts, :waiting?, false)
    }
  end

  defp entry(%ResultEntry{} = entry), do: entry

  defp entry(%{title: title} = map) do
    ResultEntry.new(title,
      metadata: Map.get(map, :metadata),
      body: Map.get(map, :body, [])
    )
  end
end
