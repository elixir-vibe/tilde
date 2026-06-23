defmodule Tilde.Transport.Live.SlashCommandTest do
  use TildeTest.Case

  alias Tilde.Transport.Live.SlashCommand

  test "slash command link completes input without submitting" do
    html =
      render_component(&SlashCommand.slash_command/1,
        label: "/new",
        insert: "/new "
      )

    assert html =~ ~s|href="#"|
    assert html =~ ~s|class="action normal"|
    assert html =~ ~s|phx-click="tilde:complete_input"|
    assert html =~ ~s|phx-value-insert="/new "|
    assert html =~ "/new"
  end

  test "slash command list reuses complete-input links with separators" do
    commands = [
      Tilde.Command.Builtin.Help.spec(),
      Tilde.Command.Builtin.Showcase.spec(),
      Tilde.Command.Builtin.New.spec()
    ]

    html = render_component(&SlashCommand.slash_commands/1, commands: commands)

    assert html =~ ~s|role="navigation"|
    assert html =~ ~s|aria-label="commands"|
    assert html =~ ">/help</a>"
    assert html =~ ">/showcase</a>"
    assert html =~ " · "
    assert html =~ ~s|phx-value-insert="/help"|
    assert html =~ ~s|phx-value-insert="/showcase"|
    assert html =~ ~s|phx-value-insert="/new "|
  end
end
