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
      "background-logs" => Tilde.Tool.Viewer.Background,
      "background-list" => Tilde.Tool.Viewer.Background,
      "background-start" => Tilde.Tool.Viewer.Background,
      "background-stop" => Tilde.Tool.Viewer.Background,
      "bash" => Tilde.Tool.Viewer.Bash,
      "fetch" => Tilde.Tool.Viewer.Fetch,
      "websearch" => Tilde.Tool.Viewer.WebSearch,
      "utc_now" => Tilde.Tool.Viewer.UtcNow
    }
  end
end
