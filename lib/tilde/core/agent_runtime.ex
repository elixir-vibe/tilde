defmodule Tilde.Core.AgentRuntime do
  @moduledoc "Durable, storage-safe metadata for an agent runtime turn."

  @enforce_keys [:active?]
  defstruct active?: false,
            input_index: nil,
            block_id: nil,
            queue_length: 0,
            run_id: nil,
            request_id: nil,
            checkpoint_token: nil,
            iteration: nil

  @type t :: %__MODULE__{
          active?: boolean(),
          input_index: pos_integer() | nil,
          block_id: String.t() | nil,
          queue_length: non_neg_integer(),
          run_id: String.t() | nil,
          request_id: String.t() | nil,
          checkpoint_token: String.t() | nil,
          iteration: non_neg_integer() | nil
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    %__MODULE__{
      active?: field(attrs, :active?, "active?", false) == true,
      input_index: field(attrs, :input_index, "input_index"),
      block_id: field(attrs, :block_id, "block_id"),
      queue_length: field(attrs, :queue_length, "queue_length", 0) || 0,
      run_id: field(attrs, :run_id, "run_id"),
      request_id: field(attrs, :request_id, "request_id"),
      checkpoint_token: field(attrs, :checkpoint_token, "checkpoint_token"),
      iteration: field(attrs, :iteration, "iteration")
    }
  end

  @spec clear() :: t()
  def clear, do: new()

  @spec from_agent_loop(map()) :: t()
  def from_agent_loop(agent_loop) when is_map(agent_loop) do
    run = Map.get(agent_loop, :run, Map.get(agent_loop, "run"))

    new(
      active?: field(agent_loop, :active?, "active?", false),
      input_index: field(agent_loop, :input_index, "input_index"),
      block_id: field(agent_loop, :block_id, "block_id"),
      queue_length: field(agent_loop, :queue_length, "queue_length", 0),
      run_id: run_field(run, :run_id),
      request_id: run_field(run, :request_id),
      checkpoint_token: run_field(run, :checkpoint_token),
      iteration: run_field(run, :iteration)
    )
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = runtime) do
    %{
      active?: runtime.active?,
      input_index: runtime.input_index,
      block_id: runtime.block_id,
      queue_length: runtime.queue_length,
      run_id: runtime.run_id,
      request_id: runtime.request_id,
      checkpoint_token: runtime.checkpoint_token,
      iteration: runtime.iteration
    }
  end

  @spec load(map() | nil) :: t()
  def load(nil), do: clear()

  def load(%__MODULE__{} = runtime), do: runtime

  def load(map) when is_map(map), do: new(map)

  defp field(attrs, atom_key, string_key, default \\ nil) do
    attrs = Map.new(attrs)
    Map.get(attrs, atom_key, Map.get(attrs, string_key, default))
  end

  defp run_field(nil, _key), do: nil

  defp run_field(run, :run_id) when is_map(run), do: field(run, :run_id, "run_id")
  defp run_field(run, :request_id) when is_map(run), do: field(run, :request_id, "request_id")

  defp run_field(run, :checkpoint_token) when is_map(run),
    do: field(run, :checkpoint_token, "checkpoint_token")

  defp run_field(run, :iteration) when is_map(run), do: field(run, :iteration, "iteration")
end
