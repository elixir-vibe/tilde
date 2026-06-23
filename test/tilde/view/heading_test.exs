defmodule Tilde.View.HeadingTest do
  use TildeTest.Case

  alias Tilde.View.{Heading, Line, Text}

  test "builds a shared title and detail heading" do
    assert %Line{role: :title, parts: parts} = Heading.line("choice", detail: "Apply patch?")

    assert [
             %Text{text: "choice", style: :title},
             %Text{text: " Apply patch?", style: :accent}
           ] = parts
  end

  test "builds tool-like headings with segments tags and suffix" do
    heading =
      Heading.line("bash",
        segments: [%{text: "mix test", color: :accent}, %{text: ":ok", color: :success}],
        tags: ["safe"],
        suffix: "done"
      )

    assert Line.text(heading) == "bash mix test:ok [safe] (done)"

    assert Enum.map(heading.parts, & &1.style) == [
             :title,
             :accent,
             :success,
             :muted,
             :muted
           ]
  end
end
