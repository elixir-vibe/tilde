defmodule Tilde.Live.Demo do
  @moduledoc """
  Self-contained LiveView demo for Tilde.

  Mount this LiveView in a Phoenix router while dogfooding the package:

      live "/tilde", Tilde.Live.Demo

  It exercises the semantic session model, the LiveView renderer, tool
  expansion, choice selection, input submission, widgets, and footer status.
  """

  use Phoenix.LiveView

  import Tilde.Live.Console

  alias Tilde.{Block, Choice, Session}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, session: demo_session(), input: "", running?: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>{Tilde.Live.Styles.css()}</style>
    <.console session={@session} input={@input} running?={@running?} />
    <details class="tilde-demo-hooks">
      <summary>Keyboard hook</summary>
      <p class="tilde-muted">
        Add this hook to your LiveSocket setup, then focus a tool block and press ctrl+o.
      </p>
      <pre><code>{Tilde.Live.Hooks.js()}</code></pre>
    </details>
    """
  end

  @impl true
  def handle_event("tilde:toggle_expand", %{"id" => id}, socket) do
    {:noreply, update(socket, :session, &Session.toggle_expand(&1, id))}
  end

  def handle_event(
        "tilde:select_choice",
        %{"block-id" => block_id, "option-id" => option_id},
        socket
      ) do
    {:noreply, update(socket, :session, &Session.select_choice(&1, block_id, option_id))}
  end

  def handle_event("tilde:choice_action", %{"action-id" => action_id}, socket) do
    session = Session.put_status(socket.assigns.session, "choice", action_id)
    {:noreply, assign(socket, session: session)}
  end

  def handle_event("tilde:submit", %{"input" => input}, socket) do
    session =
      socket.assigns.session
      |> Session.append_event(Tilde.user_message(input))
      |> Session.put_status("last input", compact(input))

    {:noreply, assign(socket, session: session, input: "")}
  end

  def handle_event("tilde:interrupt", _params, socket) do
    session = Session.put_status(socket.assigns.session, "runtime", "interrupted")
    {:noreply, assign(socket, session: session, running?: false)}
  end

  @doc "Returns the static semantic session used by the demo LiveView."
  @spec demo_session() :: Session.t()
  def demo_session do
    choice =
      Choice.new("Apply the generated patch?", [
        {"apply", "Apply", "Update the working tree"},
        {"show_diff", "Show diff first", "Review changes before applying"},
        {"skip", "Skip", "Leave files unchanged"}
      ])

    Tilde.session(id: "tilde_demo")
    |> Session.append_events([
      Tilde.user_message("Build a pi-like console on the web", id: "evt_demo_user"),
      Tilde.assistant_done("I'll inspect the project and sketch a semantic model.",
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
    |> Session.put_widget(Tilde.widget("status", :below_input, "background: no running jobs"))
    |> Session.put_status("model", "demo")
    |> Session.put_status("cwd", "~/Development/elixir-vibe/tilde")
  end

  defp append_choice_block(%Session{} = session, id, %Choice{} = choice) do
    transcript = %{
      session.transcript
      | blocks: session.transcript.blocks ++ [Block.choice(id, choice)]
    }

    %{session | transcript: transcript}
  end

  defp compact(input) do
    input
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 80)
  end
end
