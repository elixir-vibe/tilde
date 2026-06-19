defmodule Tilde.Runtime.MarkdownTest do
  use TildeTest.Case

  test "facade uses configured backend" do
    with_application_env(:markdown_backend, TildeTest.MarkdownBackend, fn ->
      assert Tilde.Runtime.Markdown.backend() == TildeTest.MarkdownBackend
      assert Tilde.Runtime.Markdown.to_html("hello") == {:ok, "<p>fake hello</p>"}
    end)
  end

  test "uses MDEx for safe HTML" do
    assert {:ok, html} = Tilde.Runtime.Markdown.to_html("**bold** and `code`")
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<code>code</code>"

    assert {:ok, safe_html} = Tilde.Runtime.Markdown.to_html("<script>alert(1)</script>")
    refute safe_html =~ "<script>"

    assert {:ok, table_html} =
             Tilde.Runtime.Markdown.to_html(
               "| name | status |\n| --- | ---: |\n| LiveView | ok |"
             )

    assert table_html =~ "<table>"
    assert table_html =~ "<th>name</th>"
    assert table_html =~ "<td>LiveView</td>"
  end

  test "can complete streaming fragments with MDEx" do
    assert {:ok, bold_html} = Tilde.Runtime.Markdown.to_html("**Fol", streaming: true)
    assert bold_html =~ "<strong>Fol</strong>"

    assert {:ok, table_html} =
             Tilde.Runtime.Markdown.to_html(
               "| surface | renderer\n| --- | ---\n| web | LiveView",
               streaming: true
             )

    assert table_html =~ "<table>"
    assert table_html =~ "<td>LiveView</td>"

    assert {:ok, safe_html} =
             Tilde.Runtime.Markdown.to_html("<script>alert(1)</script>", streaming: true)

    refute safe_html =~ "<script>"
  end
end
