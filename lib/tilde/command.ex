defmodule Tilde.Command do
  @moduledoc """
  Semantic slash command parser and dispatcher.
  """

  alias Tilde.Command.Registry
  alias Tilde.Core.Session

  defstruct name: nil, args: "", raw: ""

  @type t :: %__MODULE__{name: String.t(), args: String.t(), raw: String.t()}
  @type effect :: Tilde.Command.Effect.t()

  @doc "Parses a slash command."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(input) when is_binary(input) do
    input = String.trim(input)

    with <<"/", rest::binary>> <- input,
         [name | args] <- String.split(rest, ~r/\s+/, parts: 2),
         name = String.downcase(name),
         true <- command_name?(name),
         module when not is_nil(module) <- Registry.fetch(name) do
      {:ok,
       %__MODULE__{
         name: name,
         args: args |> Enum.join(" ") |> String.trim(),
         raw: input
       }}
    else
      _other -> :error
    end
  end

  @doc "Returns true when input is a slash command."
  @spec command?(String.t()) :: boolean()
  def command?(input), do: match?({:ok, _command}, parse(input))

  @doc "Returns command suggestions for slash input."
  @spec suggestions(String.t()) :: Tilde.Core.Suggest.t() | nil
  def suggestions(input) when is_binary(input) do
    input = String.trim_leading(input)

    case input do
      <<"/", query::binary>> ->
        query = String.downcase(query)

        items =
          Enum.filter(Registry.specs(), fn %{label: label} ->
            label |> String.trim_leading("/") |> String.starts_with?(query)
          end)

        if items == [],
          do: nil,
          else:
            Tilde.Core.Suggest.new(
              id: "command-suggestions",
              title: "commands",
              trigger: "/",
              query: query,
              items: items
            )

      _other ->
        nil
    end
  end

  @doc "Returns the selected command completion for slash input."
  @spec completion(String.t() | Tilde.Core.Suggest.t()) :: String.t() | nil
  def completion(input) when is_binary(input) do
    case suggestions(input) do
      %Tilde.Core.Suggest{} = suggest -> completion(suggest)
      _other -> nil
    end
  end

  def completion(%Tilde.Core.Suggest{} = suggest) do
    case Tilde.Core.Suggest.selected(suggest) do
      %{insert: insert} -> insert
      _other -> nil
    end
  end

  @doc "Runs a command against a session and returns semantic effects."
  @spec run(t(), Session.t(), keyword()) :: [effect()]
  def run(%__MODULE__{} = command, %Session{} = session, opts) do
    command.name
    |> Registry.fetch()
    |> case do
      nil -> []
      module -> module.run(command, session, opts)
    end
  end

  @doc "Applies command effects to a session."
  @spec apply_effects(Session.t(), [effect()]) :: Session.t()
  def apply_effects(%Session{} = session, effects) do
    Enum.reduce(effects, session, fn
      %Tilde.Command.Effect.ReplaceSession{session: replacement}, _session ->
        replacement

      %Tilde.Command.Effect.AppendEvent{event: event}, session ->
        Session.append_event(session, event)

      %Tilde.Command.Effect.NewSession{}, session ->
        session

      :ok, session ->
        session
    end)
  end

  @doc "Returns a new-session id from optional command args."
  @spec new_session_id(String.t()) :: String.t()
  def new_session_id(""), do: "s-#{System.unique_integer([:positive])}"

  def new_session_id(args) do
    args
    |> Tilde.Session.Registry.normalize_id()
    |> case do
      "shared" -> new_session_id("")
      id -> id
    end
  end

  defp command_name?(name), do: String.match?(name, ~r/^[A-Za-z][A-Za-z0-9_-]*$/)
end
