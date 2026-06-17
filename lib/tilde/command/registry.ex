defmodule Tilde.Command.Registry do
  @moduledoc "Registry for built-in semantic slash commands."

  @builtins [
    Tilde.Command.Builtin.Help,
    Tilde.Command.Builtin.New,
    Tilde.Command.Builtin.Attach,
    Tilde.Command.Builtin.Detach,
    Tilde.Command.Builtin.Session,
    Tilde.Command.Builtin.Clear,
    Tilde.Command.Builtin.Compact,
    Tilde.Command.Builtin.Quit
  ]

  @spec modules() :: [module()]
  def modules, do: Application.get_env(:tilde, :commands, @builtins)

  @spec specs() :: [Tilde.Command.Spec.t()]
  def specs, do: Enum.map(modules(), & &1.spec())

  @spec fetch(String.t()) :: module() | nil
  def fetch(name) do
    Enum.find(modules(), fn module -> command_name(module.spec().label) == name end)
  end

  defp command_name("/" <> name), do: name
end
