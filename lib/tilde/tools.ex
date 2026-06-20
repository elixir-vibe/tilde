defmodule Tilde.Tools do
  @moduledoc "Tool sets available to Tilde's Jido-backed assistant runtime."

  @doc "Safe demo tools."
  @spec demo_tools() :: [module()]
  def demo_tools, do: [Tilde.Tools.UtcNow]

  @doc "Coding tools exposed to the assistant."
  @spec coding_tools() :: [module()]
  def coding_tools do
    [
      Tilde.Tools.List,
      Tilde.Tools.Read,
      Tilde.Tools.Edit,
      Tilde.Tools.Write,
      Tilde.Tools.Bash,
      Tilde.Tools.UtcNow
    ]
  end
end
