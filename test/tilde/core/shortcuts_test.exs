defmodule Tilde.Core.ShortcutsTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Shortcuts

  test "renders keys from semantic shortcut ids" do
    assert Shortcuts.display_key("tilde.workspace.view_files") == "f"
    assert Shortcuts.display_key("tilde.workspace.view_symbols") == "s"
    assert Shortcuts.display_key("tilde.session.chat") == "escape"
    assert Shortcuts.display_key("tilde.review.focus") == "r"
    assert Shortcuts.label("tilde.workspace.view_files") == "files"
    assert Shortcuts.label("tilde.workspace.view_symbols") == "symbols"
    assert Shortcuts.label("tilde.session.chat") == "chat"
    assert Shortcuts.label("tilde.review.focus") == "review"
    assert Shortcuts.display_key("tilde.workspace.focus_previous") == "arrowup"
    assert Shortcuts.display_key("tilde.workspace.focus_next") == "arrowdown"
    assert Shortcuts.display_key("tilde.workspace.open_focused") == "enter"
    assert Shortcuts.display_key("tilde.palette.open") == "ctrl+p"
    assert Shortcuts.display_key("tilde.palette.mode_files") == "f"
    assert Shortcuts.display_key("tilde.palette.mode_symbols") == "s"
    assert Shortcuts.display_key("tilde.palette.accept") == "enter"
  end

  test "exposes browser bindings from semantic definitions" do
    bindings = Shortcuts.browser_bindings()

    assert %{
             "id" => "tilde.palette.open",
             "keys" => ["ctrl+p"],
             "scopes" => ["chat", "workspace", "buffer", "palette"],
             "preventDefault" => true,
             "captureInteractive" => true
           } in bindings

    assert %{
             "id" => "tilde.workspace.view_files",
             "keys" => ["f"],
             "scopes" => ["chat", "workspace", "buffer"],
             "preventDefault" => false,
             "captureInteractive" => false
           } in bindings

    assert %{
             "id" => "tilde.review.focus",
             "keys" => ["r"],
             "scopes" => ["buffer"],
             "preventDefault" => true,
             "captureInteractive" => false
           } in bindings
  end

  test "matches keys only in their declared scopes" do
    assert Shortcuts.match(:chat, "f") == "tilde.workspace.view_files"
    assert Shortcuts.match(:workspace, "f") == "tilde.workspace.view_files"
    assert Shortcuts.match(:buffer, "S") == "tilde.workspace.view_symbols"
    assert Shortcuts.match(:buffer, "Escape") == "tilde.session.chat"
    assert Shortcuts.match(:buffer, "r") == "tilde.review.focus"
    assert Shortcuts.match(:workspace, "ArrowUp") == "tilde.workspace.focus_previous"
    assert Shortcuts.match(:workspace, "k") == "tilde.workspace.focus_previous"
    assert Shortcuts.match(:workspace, "ArrowDown") == "tilde.workspace.focus_next"
    assert Shortcuts.match(:workspace, "j") == "tilde.workspace.focus_next"
    assert Shortcuts.match(:workspace, "Enter") == "tilde.workspace.open_focused"
    assert Shortcuts.match(:chat, "ctrl+p") == "tilde.palette.open"
    assert Shortcuts.match(:palette, "ctrl+p") == "tilde.palette.open"
    assert Shortcuts.match(:palette, "f") == "tilde.palette.mode_files"
    assert Shortcuts.match(:palette, "s") == "tilde.palette.mode_symbols"
    assert Shortcuts.match(:palette, "Escape") == "tilde.palette.close"
    assert Shortcuts.match(:palette, "ArrowUp") == "tilde.palette.previous"
    assert Shortcuts.match(:palette, "ArrowDown") == "tilde.palette.next"
    assert Shortcuts.match(:palette, "Enter") == "tilde.palette.accept"

    refute Shortcuts.match(:chat, "escape")
    refute Shortcuts.match(:chat, "r")
    refute Shortcuts.match(:workspace, "r")
  end
end
