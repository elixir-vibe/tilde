defmodule Tilde.Runtime.Event do
  @moduledoc """
  Runtime-neutral event consumed by Tilde's session agent loop.

  This is the narrow contract between the model/tool runtime and the semantic
  console. It intentionally contains only the fields Tilde currently projects
  into `Tilde.Core.Event` values and durable runtime metadata. Provider-specific
  events are normalized to this struct before they reach `Tilde.Session.AgentLoop`.
  """

  @type kind ::
          :request_started
          | :request_cancelled
          | :request_completed
          | :request_failed
          | :checkpoint
          | :llm_delta
          | :tool_started
          | :tool_completed
          | atom()

  @type t :: %__MODULE__{
          seq: non_neg_integer(),
          run_id: String.t() | nil,
          request_id: String.t() | nil,
          iteration: non_neg_integer() | nil,
          kind: kind(),
          tool_call_id: String.t() | nil,
          llm_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          data: map()
        }

  defstruct seq: 0,
            run_id: nil,
            request_id: nil,
            iteration: nil,
            kind: nil,
            tool_call_id: nil,
            llm_call_id: nil,
            tool_name: nil,
            data: %{}

  @doc "Builds a runtime event from map or keyword attributes."
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      seq: field(attrs, :seq, 0) || 0,
      run_id: field(attrs, :run_id),
      request_id: field(attrs, :request_id),
      iteration: field(attrs, :iteration),
      kind: field(attrs, :kind),
      tool_call_id: field(attrs, :tool_call_id),
      llm_call_id: field(attrs, :llm_call_id),
      tool_name: field(attrs, :tool_name),
      data: field(attrs, :data, %{}) || %{}
    }
  end

  defp field(attrs, key, default \\ nil) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
