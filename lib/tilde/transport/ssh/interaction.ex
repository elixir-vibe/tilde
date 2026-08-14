defmodule Tilde.Transport.SSH.Interaction do
  @moduledoc "Translates decoded SSH/TUI keys into core interactions."

  alias Tilde.Core.{Input, Interaction}
  alias Tilde.Index

  @type translated :: Interaction.t() | :halt | nil

  @spec index(Index.t(), Tilde.Core.Keys.key()) :: translated()
  def index(%Index{}, :enter), do: Interaction.new(:suggest_submit)
  def index(%Index{}, :down), do: Interaction.new(:suggest_next)
  def index(%Index{}, :up), do: Interaction.new(:suggest_previous)
  def index(%Index{}, :tab), do: Interaction.new(:suggest_accept)
  def index(%Index{}, :cancel), do: Interaction.new(:suggest_cancel)

  def index(%Index{input: %Input{value: ""}}, key) when key in [:quit, :interrupt], do: :halt
  def index(%Index{}, :quit), do: nil
  def index(%Index{}, :interrupt), do: Interaction.new(:interrupt)
  def index(%Index{input: %Input{value: ""}}, {:text, "n"}), do: Interaction.new(:new_shortcut)

  def index(%Index{} = index, {:text, text}) do
    input = Input.insert(index.input, text)
    Interaction.input_changed(input.value)
  end

  def index(%Index{}, _key), do: nil
end
