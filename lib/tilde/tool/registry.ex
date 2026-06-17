defmodule Tilde.Tool.Registry do
  @moduledoc """
  Resolves semantic tool viewers.
  """

  alias Tilde.Core.Block

  @spec fetch(Block.t() | String.t() | nil) :: module()
  def fetch(%Block{name: name}), do: fetch(name)

  def fetch(name) do
    registry = Application.get_env(:tilde, :tool_viewers, default_registry())
    Map.get(registry, name, Tilde.Tool.Viewer.Default)
  end

  @spec default_registry() :: %{String.t() => module()}
  def default_registry do
    %{
      "bash" => Tilde.Tool.Viewer.Bash,
      "utc_now" => Tilde.Tool.Viewer.UtcNow
    }
  end
end
