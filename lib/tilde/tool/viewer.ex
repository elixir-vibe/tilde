defmodule Tilde.Tool.Viewer do
  @moduledoc """
  Behaviour for deriving renderer-neutral tool call/result views from tool blocks.
  """

  alias Tilde.Core.Block
  alias Tilde.Tool.View

  @callback call(Block.t()) :: View.call()
  @callback result(Block.t(), keyword()) :: View.result()
end
