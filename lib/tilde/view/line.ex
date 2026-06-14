defmodule Tilde.View.Line do
  @moduledoc """
  Shared renderer-neutral view line.
  """

  alias Tilde.View.Text

  defstruct parts: [], role: :normal

  @type role :: :normal | :metadata | :primary | :muted | :error | :title | :hint
  @type t :: %__MODULE__{parts: [Text.t()], role: role()}

  @spec new([Text.t() | String.t()] | Text.t() | String.t(), keyword()) :: t()
  def new(parts, opts \\ []) do
    parts = parts |> List.wrap() |> Enum.map(&normalize_part/1)
    %__MODULE__{parts: parts, role: Keyword.get(opts, :role, :normal)}
  end

  @spec text(t()) :: String.t()
  def text(%__MODULE__{parts: parts}), do: Enum.map_join(parts, & &1.text)

  defp normalize_part(%Text{} = part), do: part
  defp normalize_part(part), do: Text.new(part)
end
