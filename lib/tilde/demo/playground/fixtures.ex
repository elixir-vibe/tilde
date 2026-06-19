defmodule Tilde.Demo.Playground.Fixtures do
  @moduledoc "Static semantic sessions used by the web component playground."

  alias Tilde.Core.{Block, Choice, Session}

  @type section :: %{
          id: String.t(),
          title: String.t(),
          description: String.t(),
          session: Session.t()
        }

  @spec sections() :: [section()]
  def sections do
    [
      tool_success(),
      tool_error(),
      streaming_logs(),
      long_output(),
      read_file(),
      edit_file(),
      choice_picker(),
      thinking_turn(),
      search_results()
    ]
  end

  defp tool_success do
    session =
      session("playground-tool-success")
      |> Session.append_events([
        Tilde.user_message("Run focused tests"),
        Tilde.assistant_done("I'll run the focused test file."),
        Tilde.tool_started("bash", %{command: "mix test test/tilde/demo/playground_test.exs"},
          tool_call_id: "pg_tool_success"
        ),
        Tilde.tool_stream("pg_tool_success", :stdout, "Compiling 2 files...\n"),
        Tilde.tool_stream("pg_tool_success", :stdout, "Running ExUnit...\n"),
        Tilde.tool_stream("pg_tool_success", :stdout, "......\n"),
        Tilde.tool_stream("pg_tool_success", :stdout, "6 tests, 0 failures\n"),
        Tilde.tool_done("pg_tool_success", :success, %{exit_code: 0})
      ])

    section("tool-success", "Tool success", "Completed tool call with compact output.", session)
  end

  defp tool_error do
    session =
      session("playground-tool-error")
      |> Session.append_events([
        Tilde.user_message("Run a missing command"),
        Tilde.assistant_done("I'll execute the command and show stderr if it fails."),
        Tilde.tool_started("bash", %{command: "missing-command"}, tool_call_id: "pg_tool_error"),
        Tilde.tool_stream("pg_tool_error", :stderr, "sh: missing-command: command not found\n"),
        Tilde.tool_done("pg_tool_error", :error, %{exit_code: 127})
      ])

    section("tool-error", "Tool error", "Failed tool call and stderr rendering.", session)
  end

  defp streaming_logs do
    session =
      session("playground-streaming-logs")
      |> Session.append_events([
        Tilde.user_message("Start the dev server"),
        Tilde.assistant_done("I'll start it as a background process."),
        Tilde.tool_started("background-start", %{name: "demo-server", command: "mix phx.server"},
          tool_call_id: "pg_logs"
        ),
        Tilde.tool_stream(
          "pg_logs",
          :stdout,
          "[info] Running endpoint at http://127.0.0.1:4000\n"
        ),
        Tilde.tool_stream("pg_logs", :stdout, "[debug] Processing with Tilde.Demo.Live\n"),
        Tilde.tool_stream("pg_logs", :stdout, "[info] Sent 200 in 4ms\n"),
        Tilde.tool_done("pg_logs", :success, %{pid: 12_345, log: "/tmp/pi-bg/demo-server.log"})
      ])

    section("streaming-logs", "Streaming logs", "Background-process style log output.", session)
  end

  defp long_output do
    lines = Enum.map_join(1..12, "\n", &"result row #{&1}: semantic output preview") <> "\n"

    session =
      session("playground-long-output")
      |> Session.append_events([
        Tilde.user_message("Fetch a long result"),
        Tilde.assistant_done("I'll fetch the page and keep the output compact."),
        Tilde.tool_started("fetch", %{url: "https://example.test/large", format: "markdown"},
          tool_call_id: "pg_long"
        ),
        Tilde.tool_stream("pg_long", :stdout, lines),
        Tilde.tool_done("pg_long", :success, %{truncated: true})
      ])
      |> Session.update_block("pg_long", &Block.update_display(&1, %{compact_limit: {:lines, 4}}))

    section("long-output", "Long output", "Compact truncation and expand affordance.", session)
  end

  defp read_file do
    text = Enum.map_join(1..6, "\n", &"def example_#{&1}, do: :ok") <> "\n"

    session =
      session("playground-read-file")
      |> Session.append_events([
        Tilde.user_message("Read the renderer module"),
        Tilde.assistant_done("I'll read the relevant line range."),
        Tilde.tool_started(
          "read",
          %{path: "lib/tilde/transport/live/view_renderer.ex", offset: 10, limit: 6},
          tool_call_id: "pg_read"
        ),
        Tilde.tool_done("pg_read", :success, %{content: [%{type: "text", text: text}]})
      ])

    section("read-file", "Read file", "Read tool call with compact expansion.", session)
  end

  defp edit_file do
    diff = """
    @@ -1,3 +1,3 @@
    -old_call(:background_start)
    +new_call(:bg_start)
     unchanged()
    """

    session =
      session("playground-edit-file")
      |> Session.append_events([
        Tilde.user_message("Patch the display label"),
        Tilde.assistant_done("I'll apply an exact replacement."),
        Tilde.tool_started("edit", %{path: "lib/tilde/tool/registry.ex"},
          tool_call_id: "pg_edit"
        ),
        Tilde.tool_done("pg_edit", :success, %{diff: diff})
      ])

    section("edit-file", "Edit file", "Edit tool call with semantic diff output.", session)
  end

  defp choice_picker do
    choice =
      Choice.new("Apply the generated patch?", [
        {"apply", "Apply", "Update the working tree"},
        {"show-diff", "Show diff first", "Review changes before applying"},
        {"skip", "Skip", "Leave files unchanged"}
      ])

    session =
      session("playground-choice")
      |> Session.append_events([
        Tilde.user_message("What should I do with the patch?"),
        Tilde.assistant_done("Choose the next action.")
      ])
      |> append_block(Block.choice("pg_choice", choice))

    section(
      "choice-picker",
      "Choice picker",
      "Transport-neutral selectable choice block.",
      session
    )
  end

  defp thinking_turn do
    block_id = "pg_assistant_thinking"

    session =
      session("playground-thinking")
      |> Session.append_events([
        Tilde.user_message("Explain the rendering model"),
        Tilde.assistant_turn_started(block_id: block_id),
        Tilde.assistant_delta("I need to separate semantic state from DOM projection.\n",
          block_id: block_id,
          metadata: %{chunk_type: :thinking}
        ),
        Tilde.assistant_delta(
          "Tilde keeps events and blocks semantic; LiveView only projects them.",
          block_id: block_id,
          metadata: %{chunk_type: :content}
        ),
        Tilde.assistant_turn_finished(block_id: block_id)
      ])

    section(
      "thinking-turn",
      "Thinking turn",
      "Reasoning metadata without polluting answer text.",
      session
    )
  end

  defp search_results do
    results = [
      search_result(
        "Pi Tools",
        "https://example.test/pi-tools",
        "semantic tool rendering, compact previews, expandable details"
      ),
      search_result(
        "Code Search",
        "https://example.test/code-search",
        "repository metadata, path:line snippets, focused fetches"
      ),
      search_result(
        "Worktrees",
        "https://example.test/worktrees",
        "branch isolation, status summaries, cleanup actions"
      )
    ]

    output = """
    Title: Pi Tools
    URL: https://example.test/pi-tools
    Highlights:
    - semantic tool rendering, compact previews, expandable details

    ---

    Title: Code Search
    URL: https://example.test/code-search
    Highlights:
    - repository metadata, path:line snippets, focused fetches

    ---

    Title: Worktrees
    URL: https://example.test/worktrees
    Highlights:
    - branch isolation, status summaries, cleanup actions
    """

    session =
      session("playground-search")
      |> Session.append_events([
        Tilde.user_message("Search for pi tool UI examples"),
        Tilde.assistant_done("I'll search and summarize the strongest matches."),
        Tilde.tool_started("websearch", %{query: "pi tool UI examples"},
          tool_call_id: "pg_search"
        ),
        Tilde.tool_stream("pg_search", :stdout, output),
        Tilde.tool_done("pg_search", :success, %{results: results, output: output})
      ])

    section(
      "search-results",
      "Search results",
      "Search-style cards as current semantic output pressure.",
      session
    )
  end

  defp section(id, title, description, %Session{} = session) do
    %{id: id, title: title, description: description, session: session}
  end

  defp search_result(title, url, highlight) do
    %{title: title, url: url, highlights: [highlight]}
  end

  defp session(id), do: Tilde.session(id: id)

  defp append_block(%Session{} = session, %Block{} = block) do
    transcript = %{session.transcript | blocks: session.transcript.blocks ++ [block]}
    %{session | transcript: transcript}
  end
end
