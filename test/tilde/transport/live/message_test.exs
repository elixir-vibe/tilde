defmodule Tilde.Transport.Live.MessageTest do
  use TildeTest.Case

  test "renders markdown source with MDEx" do
    block = Block.message("msg_1", :assistant, "**bold** and `code`")
    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)

    assert html =~ "markdown"
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<code>code</code>"
  end

  test "renders semantic runs as inline HTML" do
    block =
      Block.message("msg_1", :assistant, "",
        runs: [
          Run.new("bold", [:bold]),
          Run.new(" "),
          Run.new("under", [:underline]),
          Run.new(" "),
          Run.new("code", [:code]),
          Run.new(" link", [], %{href: "https://example.test"})
        ]
      )

    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)

    assert html =~ "<strong>"
    assert html =~ "bold"
    assert html =~ "<u>"
    assert html =~ "under"
    assert html =~ "<code>"
    assert html =~ "code"
    assert html =~ "href=\"https://example.test\""
  end
end
