defmodule Tilde.Renderer.JSONTest do
  use TildeTest.Case

  test "returns JSON-compatible semantic data" do
    transcript =
      [
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
        Tilde.tool_stream("tool_1", :stdout, "ok\n")
      ]
      |> Transcript.from_events()

    rendered = Renderer.JSON.render(transcript)

    assert [%{kind: :tool, streams: [stream]}] = rendered.blocks
    assert stream.chunks == ["ok\n"]
    assert stream.text == "ok\n"
    assert stream.line_count == 1
    assert stream.byte_count == 3
  end
end
