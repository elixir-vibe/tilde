defmodule Tilde.Tool.View do
  @moduledoc "Semantic tool view constructors."

  alias Tilde.Tool.View.{Call, Result, Segment}

  @type segment :: Segment.t()
  @type call :: Call.t()
  @type result :: Result.t()

  @spec call(String.t(), keyword()) :: Call.t()
  def call(title, opts \\ []), do: Call.new(title, opts)

  @spec result(keyword()) :: Result.t()
  def result(opts \\ []), do: Result.new(opts)

  @spec segment(String.t(), keyword()) :: Segment.t()
  def segment(text, opts \\ []), do: Segment.new(text, opts)
end
