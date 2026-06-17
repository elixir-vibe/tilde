defmodule Tilde.Transport.SSH.Command do
  @moduledoc """
  SSH transport commands.

  These commands affect the SSH channel/session attachment, not the semantic
  transcript itself. Ordinary slash commands remain in `Tilde.Command`.
  """

  alias Tilde.Session.Registry, as: SessionRegistry

  @type t :: {:attach, String.t()} | :detach | :session | :submit

  @doc "Parses SSH transport commands from a prompt value."
  @spec parse(String.t()) :: t()
  def parse(input) when is_binary(input) do
    case Tilde.Command.parse(input) do
      {:ok, %Tilde.Command{name: "attach", args: args}} when args != "" ->
        {:attach, SessionRegistry.normalize_id(args)}

      {:ok, %Tilde.Command{name: "attach"}} ->
        {:attach, "shared"}

      {:ok, %Tilde.Command{name: "detach"}} ->
        :detach

      {:ok, %Tilde.Command{name: "session"}} ->
        :session

      _other ->
        :submit
    end
  end

  def parse(_input), do: :submit
end
