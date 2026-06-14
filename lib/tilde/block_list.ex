defmodule Tilde.BlockList do
  @moduledoc false

  alias Tilde.Block

  @spec update([Block.t()], String.t() | nil, (Block.t() -> Block.t())) :: [Block.t()]
  def update(blocks, nil, _fun), do: blocks

  def update(blocks, block_id, fun) when is_binary(block_id) and is_function(fun, 1) do
    Enum.map(blocks, fn
      %Block{id: ^block_id} = block -> fun.(block)
      %Block{} = block -> block
    end)
  end
end
