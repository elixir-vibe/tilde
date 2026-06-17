defprotocol Tilde.Viewable do
  @moduledoc """
  Converts semantic data structures into renderer-neutral `Tilde.View.Cell` data.

  Renderers consume view cells; core structs do not know about LiveView, ANSI, or
  transport details.
  """

  @spec to_view(t()) :: Tilde.View.Cell.t()
  def to_view(data)

  @spec to_view(t(), keyword()) :: Tilde.View.Cell.t()
  def to_view(data, opts)
end
