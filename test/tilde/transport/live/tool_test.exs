defmodule Tilde.Transport.Live.ToolTest do
  use TildeTest.Case

  test "renders through shared semantic view cells" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test", cwd: "/tmp/app"},
        display: %Display{compact_limit: {:lines, 3}}
      )
      |> Block.append_stream(:stdout, "ok\n")
      |> Block.append_stream(:stderr, "warning\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    html = render_component(&Tilde.Transport.Live.Tool.tool/1, block: tool)

    assert html =~ ~s|class="lines"|
    assert html =~ ~s|class="text muted">stdout|
    assert html =~ ~s|class="text muted">stderr|
    assert html =~ ~s|class="text primary">  ok|
    assert html =~ ~s|class="text primary">  warning|
    refute html =~ "tool-stream-stdout"
    refute html =~ "/tmp/app"
  end

  test "compact tool has a single expand affordance" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.append_stream(:stdout, "one\ntwo\nthree\nfour\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    html = render_component(&Tilde.Transport.Live.Tool.tool/1, block: tool)

    refute html =~ "more stdout lines"
    assert html =~ "… 2 more lines"
    assert html =~ "ctrl+o"
    assert html =~ "expand"
  end
end
