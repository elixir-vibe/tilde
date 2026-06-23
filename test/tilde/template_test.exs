defmodule Tilde.TemplateTest do
  use TildeTest.Case

  test "semantic HEEx components render to cells, LiveView, and TUI" do
    require Tilde.Template
    require Tilde.Template.Renderer.Live
    require Tilde.Template.Renderer.TUI

    source = """
    <.cell kind="template" state="success" padding_x={1} padding_y={0}>
      <.tool_call name="bash" segment="mix test" />
      <.line role="metadata"><.meta>cwd /tmp/app  exit 0</.meta></.line>
      <.line role="primary"><.primary>ok</.primary></.line>
    </.cell>
    """

    [cell] = Tilde.Template.to_cells!(source)

    assert cell.kind == :template
    assert cell.state == :success
    assert cell.padding_x == 1

    assert Enum.map(cell.lines, &Tilde.View.Helpers.plain_text/1) == [
             "bash mix test",
             "cwd /tmp/app  exit 0",
             "ok"
           ]

    assert [%{style: :title}, %{style: :accent}] = hd(cell.lines).parts
    assert List.last(cell.lines).role == :primary

    live = source |> Tilde.Template.Renderer.Live.render!() |> rendered_to_string()
    tui = Tilde.Template.Renderer.TUI.render!(source, 50)

    assert live =~ ~s|class="text title"|
    assert live =~ ~s|class="text accent"|
    assert strip_ansi(tui) =~ "bash mix test"
    assert strip_ansi(tui) =~ "ok"
    assert tui =~ IO.ANSI.bright()
  end

  test "semantic HEEx templates compose widgets" do
    require Tilde.Template

    [screen] =
      Tilde.Template.to_widgets!(
        """
        <.screen id="home" class="index">
          <.widget_text id="title" text="tilde" kind="heading" />
          <.dialog id="confirm" title="Confirm" body="Continue?" actions={@actions} />
          <.widget_input id="input" input={@input} />
          <.shortcut_bar id="shortcuts" shortcuts={@shortcuts} />
        </.screen>
        """,
        assigns: %{
          input: %Tilde.Core.Input{value: "/new ", cursor: 5},
          shortcuts: [%{key: "n", label: "new"}],
          actions: [Tilde.action(:ok, "OK", key: "enter")]
        }
      )

    assert_widget(screen, id: "home", kind: :screen, metadata: %{class: "index"})
    assert_widget_text(screen, "tilde")
    assert_shortcut(screen, key: "n", label: "new")
    assert_widget(screen, id: "confirm", kind: :dialog)
    assert Enum.map(screen.children, & &1.kind) == [:heading, :dialog, :input, :shortcut_bar]
  end

  test "semantic HEEx templates support assigns, message cells, and markdown" do
    require Tilde.Template
    require Tilde.Template.Renderer.Live
    require Tilde.Template.Renderer.TUI

    source = """
    <.message role={@role}>
      Hello <.title>{@name}</.title>
    </.message>
    <.markdown role="assistant">
      **streaming** markdown
    </.markdown>
    """

    [message, markdown] = Tilde.Template.to_cells!(source, assigns: %{role: "user", name: "Ada"})

    assert message.kind == :message
    assert message.role == :user
    assert message.source == "Hello Ada"
    assert Enum.any?(hd(message.lines).parts, &(&1.style == :title and &1.text == "Ada"))

    assert markdown.kind == :message
    assert markdown.role == :assistant
    assert markdown.format == :markdown
    assert markdown.source == "**streaming** markdown"

    live =
      source
      |> Tilde.Template.Renderer.Live.render!(assigns: %{role: "user", name: "Ada"})
      |> rendered_to_string()

    tui = Tilde.Template.Renderer.TUI.render!(source, 50, assigns: %{role: "user", name: "Ada"})

    assert live =~ "Hello"
    assert strip_ansi(tui) =~ "Hello Ada"
  end

  test "semantic HEEx source walker supports lists, code blocks, and tables" do
    require Tilde.Template

    [cell] =
      Tilde.Template.to_cells!("""
      <.cell>
        <ul><li>one</li><li><strong>two</strong></li></ul>
        <pre>mix test\nok</pre>
        <table>
          <tr><th>Name</th><th>Status</th></tr>
          <tr><td>CI</td><td><.success>green</.success></td></tr>
        </table>
      </.cell>
      """)

    assert Enum.map(cell.lines, &Tilde.View.Helpers.plain_text/1) == [
             "• one",
             "• two",
             "mix test",
             "ok",
             "Name | Status",
             "CI | green"
           ]

    assert [
             %{style: :title, text: "Name"},
             %{style: :muted, text: " | "},
             %{style: :title, text: "Status"}
           ] = Enum.at(cell.lines, 4).parts

    assert Enum.any?(List.last(cell.lines).parts, &(&1.style == :success and &1.text == "green"))
  end

  test "semantic HEEx templates report missing assigns" do
    require Tilde.Template

    assert_raise KeyError, fn ->
      Tilde.Template.to_cells!("""
      <.message>Hello {@missing}</.message>
      """)
    end
  end
end
