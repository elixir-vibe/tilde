defmodule Tilde.Demo.Showcase do
  @moduledoc "Semantic showcase content for the demo console."

  alias Tilde.Core.{Block, Choice, Session}

  @doc "Appends the showcase transcript, tool, and choice block to a session."
  @spec append(Session.t()) :: Session.t()
  def append(%Session{} = session) do
    choice =
      Choice.new("Apply the generated patch?", [
        {"apply", "Apply", "Update the working tree"},
        {"show_diff", "Show diff first", "Review changes before applying"},
        {"skip", "Skip", "Leave files unchanged"}
      ])

    session
    |> Session.append_events(events())
    |> Session.update_block(
      "tool_demo_tests",
      &Block.update_display(&1, %{compact_limit: {:lines, 2}})
    )
    |> append_choice_block("choice_demo", choice)
  end

  @doc "Returns a new session with showcase content appended."
  @spec session(keyword()) :: Session.t()
  def session(opts \\ []) do
    opts
    |> Tilde.session()
    |> append()
  end

  defp events do
    [
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

        `ctrl+o` expands tools. Type `/help` for commands, `/showcase`, or `/new` for an isolated session.
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
    ]
  end

  defp append_choice_block(%Session{} = session, id, %Choice{} = choice) do
    transcript = %{
      session.transcript
      | blocks: session.transcript.blocks ++ [Block.choice(id, choice)]
    }

    %{session | transcript: transcript}
  end
end
