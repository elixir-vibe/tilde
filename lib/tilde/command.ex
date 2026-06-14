defmodule Tilde.Command do
  @moduledoc """
  Semantic slash commands shared by LiveView and TUI/SSH renderers.
  """

  alias Tilde.Session

  defstruct name: nil, args: "", raw: ""

  @commands [
    %{label: "/help", insert: "/help", description: "Show this help"},
    %{label: "/new", insert: "/new ", description: "Start an isolated web session"},
    %{label: "/attach", insert: "/attach ", description: "Attach SSH/TUI to a named session"},
    %{label: "/session", insert: "/session", description: "Show current session details"},
    %{label: "/clear", insert: "/clear", description: "Clear this session"},
    %{label: "/compact", insert: "/compact", description: "Trim older session history"},
    %{label: "/quit", insert: "/quit", description: "Quit in SSH/TUI; not applicable on web"}
  ]

  @type t :: %__MODULE__{name: String.t(), args: String.t(), raw: String.t()}
  @type effect ::
          :ok
          | {:replace_session, Session.t()}
          | {:append_event, Tilde.Event.t()}
          | {:new_session, String.t()}

  @help """
  Available commands:

  - `/help` — Show this help
  - `/new [name]` — Start an isolated web session
  - `/attach <name>` — Attach SSH/TUI to a named session
  - `/session` — Show current session details
  - `/clear` — Clear this session
  - `/compact` — Trim older session history
  - `/quit` — Quit in SSH/TUI; not applicable on web
  """

  @doc "Parses a slash command."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(input) when is_binary(input) do
    input = String.trim(input)

    with <<"/", rest::binary>> <- input,
         [name | args] <- String.split(rest, ~r/\s+/, parts: 2),
         true <- command_name?(name) do
      {:ok,
       %__MODULE__{
         name: String.downcase(name),
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
  @spec suggestions(String.t()) :: Tilde.Suggest.t() | nil
  def suggestions(input) when is_binary(input) do
    input = String.trim_leading(input)

    case input do
      <<"/", query::binary>> ->
        query = String.downcase(query)

        items =
          Enum.filter(@commands, fn %{label: label} ->
            label |> String.trim_leading("/") |> String.starts_with?(query)
          end)

        if items == [],
          do: nil,
          else:
            Tilde.Suggest.new(
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

  @doc "Returns the first command completion for slash input."
  @spec completion(String.t()) :: String.t() | nil
  def completion(input) when is_binary(input) do
    case suggestions(input) do
      %Tilde.Suggest{items: [%{insert: insert} | _]} -> insert
      _other -> nil
    end
  end

  @doc "Runs a command against a session and returns semantic effects."
  @spec run(t(), Session.t(), keyword()) :: [effect()]
  def run(%__MODULE__{name: "help"}, %Session{}, _opts), do: [assistant(@help)]

  def run(%__MODULE__{name: "session"}, %Session{} = session, _opts) do
    text = """
    Session: #{session.id}
    Events: #{length(session.events)}
    Blocks: #{length(session.transcript.blocks)}
    """

    [assistant(text)]
  end

  def run(%__MODULE__{name: "clear"}, %Session{} = session, opts) do
    seed = Keyword.get(opts, :seed)
    cleared = if is_function(seed, 1), do: seed.(session.id), else: Tilde.session(id: session.id)
    [{:replace_session, cleared}]
  end

  def run(%__MODULE__{name: "compact"}, %Session{} = session, opts) do
    limit =
      Keyword.get(opts, :limit, Application.get_env(:tilde, :command_compact_event_limit, 40))

    compacted =
      session
      |> Session.trim_events(limit)
      |> Session.append_event(
        Tilde.assistant_done("Compacted session history to the latest #{limit} events.")
      )

    [{:replace_session, compacted}]
  end

  def run(%__MODULE__{name: "new", args: args}, %Session{}, _opts) do
    id = new_session_id(args)
    [{:new_session, id}, assistant("New isolated session: /tilde/#{id}")]
  end

  def run(%__MODULE__{name: "attach", args: ""}, %Session{}, _opts) do
    [assistant("Usage: /attach <session-name>")]
  end

  def run(%__MODULE__{name: "attach", args: args}, %Session{}, _opts) do
    id = Tilde.SessionRegistry.normalize_id(args)
    [assistant("SSH/TUI can attach to this session with `/attach #{id}`. Web: /tilde/#{id}")]
  end

  def run(%__MODULE__{name: "quit"}, %Session{}, _opts) do
    [assistant("Use q or Ctrl+C to quit in SSH/TUI. Close the browser tab on web.")]
  end

  def run(%__MODULE__{raw: raw}, %Session{}, _opts) do
    [assistant("Unknown command: #{raw}\n\n" <> @help)]
  end

  @doc "Applies command effects to a session."
  @spec apply_effects(Session.t(), [effect()]) :: Session.t()
  def apply_effects(%Session{} = session, effects) do
    Enum.reduce(effects, session, fn
      {:replace_session, replacement}, _session -> replacement
      {:append_event, event}, session -> Session.append_event(session, event)
      {:new_session, _id}, session -> session
      :ok, session -> session
    end)
  end

  @doc "Returns a new-session id from optional command args."
  @spec new_session_id(String.t()) :: String.t()
  def new_session_id(""), do: "s-#{System.unique_integer([:positive])}"

  def new_session_id(args) do
    args
    |> Tilde.SessionRegistry.normalize_id()
    |> case do
      "shared" -> new_session_id("")
      id -> id
    end
  end

  defp assistant(text), do: {:append_event, Tilde.assistant_done(text)}

  defp command_name?(name), do: String.match?(name, ~r/^[A-Za-z][A-Za-z0-9_-]*$/)
end
