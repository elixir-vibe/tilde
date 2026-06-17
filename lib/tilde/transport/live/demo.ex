defmodule Tilde.Transport.Live.Demo do
  @moduledoc """
  Self-contained LiveView demo for Tilde.

  Mount this LiveView in a Phoenix router while dogfooding the package:

      live "/tilde", Tilde.Transport.Live.Demo

  It exercises the semantic session model, the LiveView renderer, tool
  expansion, choice selection, input submission, widgets, and footer status.
  """

  use Phoenix.LiveView

  import Tilde.Transport.Live.Console

  alias Tilde.Command
  alias Tilde.Core.{Block, Choice, Session}
  alias Tilde.Session.Registry, as: SessionRegistry, as: SessionRegistry
  alias Tilde.Session.Server, as: SessionServer, as: SessionServer

  @impl true
  def mount(params, _session, socket) do
    {server, session_id} = session_server(params)
    {:ok, _pid} = SessionServer.ensure_started(server, session: demo_session(id: session_id))

    session =
      if connected?(socket),
        do: SessionServer.subscribe(server),
        else: SessionServer.get_session(server)

    {:ok,
     assign(socket,
       session_server: server,
       session: session,
       running?: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    {Phoenix.HTML.raw("<style>" <> Tilde.Transport.Live.Styles.css() <> "</style>")}
    <.console
      session={@session}
      input={@session.input.value}
      running?={@running?}
      footer_right="/help · /new"
    />
    """
  end

  @impl true
  def handle_event("tilde:toggle_expand", %{"id" => id}, socket) do
    session =
      SessionServer.update_session(socket.assigns.session_server, &Session.toggle_expand(&1, id))

    {:noreply, assign(socket, session: session)}
  end

  def handle_event(
        "tilde:select_choice",
        %{"block-id" => block_id, "option-id" => option_id},
        socket
      ) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.select_choice(&1, block_id, option_id)
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:choice_action", %{"action-id" => action_id}, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.put_status(&1, "choice", action_id)
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:input_changed", %{"input" => input}, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.append_event(&1, Tilde.input_changed(input))
      )

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:complete_input", params, socket) do
    input = Map.get(params, "insert") || complete_input(Map.get(params, "input", ""))

    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.append_event(&1, Tilde.input_changed(input))
      )

    socket =
      if input != Map.get(params, "input"),
        do: push_event(socket, "tilde:input_completed", %{insert: input}),
        else: socket

    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:submit", %{"input" => input}, socket) do
    case Command.parse(input) do
      {:ok, %Command{name: "new", args: args}} ->
        {:noreply, push_navigate(socket, to: "/tilde/#{Command.new_session_id(args)}")}

      _other ->
        session =
          SessionServer.update_session(socket.assigns.session_server, fn session ->
            session
            |> Session.append_event(Tilde.input_submitted(input))
            |> Session.put_status("last input", compact(input))
          end)

        {:noreply, assign(socket, session: session)}
    end
  end

  def handle_event("tilde:interrupt", _params, socket) do
    session =
      SessionServer.update_session(
        socket.assigns.session_server,
        &Session.put_status(&1, "runtime", "interrupted")
      )

    {:noreply, assign(socket, session: session, running?: false)}
  end

  @impl true
  def handle_info({:tilde_session_updated, _session_id, %Session{} = session}, socket) do
    {:noreply, assign(socket, session: session)}
  end

  defp session_server(%{"session_id" => session_id}) do
    session_id = SessionRegistry.normalize_id(session_id)
    {:ok, _pid} = SessionRegistry.ensure_started()
    {SessionRegistry.via(session_id), session_id}
  end

  defp session_server(_params), do: {SessionServer, "tilde_demo"}

  @doc "Returns the static semantic session used by the demo LiveView."
  @spec demo_session(keyword()) :: Session.t()
  def demo_session(opts \\ []) do
    id = Keyword.get(opts, :id, "tilde_demo")

    choice =
      Choice.new("Apply the generated patch?", [
        {"apply", "Apply", "Update the working tree"},
        {"show_diff", "Show diff first", "Review changes before applying"},
        {"skip", "Skip", "Leave files unchanged"}
      ])

    Tilde.session(id: id)
    |> Session.append_events([
      Tilde.user_message("Build a pi-like console on the web", id: "evt_demo_user"),
      Tilde.assistant_done(
        """
        I'll inspect the project and sketch a **semantic model**.

        - event log
        - semantic transcript
        - LiveView renderer

        | surface | renderer |
        | --- | --- |
        | web | LiveView DOM |
        | ssh | semantic TUI |

        `ctrl+o` expands tools. Type `/help` for commands or `/new` for an isolated session.
        """,
        id: "evt_demo_assistant"
      ),
      Tilde.tool_started("bash", %{command: "mix test", cwd: "~/Development/elixir-vibe/tilde"},
        tool_call_id: "tool_demo_tests"
      ),
      Tilde.tool_stream("tool_demo_tests", :stdout, "Compiling 3 files...\n"),
      Tilde.tool_stream("tool_demo_tests", :stdout, "Running ExUnit...\n"),
      Tilde.tool_stream("tool_demo_tests", :stdout, "........\n"),
      Tilde.tool_stream("tool_demo_tests", :stdout, "8 tests, 0 failures\n"),
      Tilde.tool_done("tool_demo_tests", :success, %{exit_code: 0})
    ])
    |> Session.update_block(
      "tool_demo_tests",
      &Block.update_display(&1, %{compact_limit: {:lines, 2}})
    )
    |> append_choice_block("choice_demo", choice)
  end

  defp append_choice_block(%Session{} = session, id, %Choice{} = choice) do
    transcript = %{
      session.transcript
      | blocks: session.transcript.blocks ++ [Block.choice(id, choice)]
    }

    %{session | transcript: transcript}
  end

  defp complete_input(input), do: Command.completion(input) || input

  defp compact(input) do
    input
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 80)
  end
end
