defmodule Tilde.Index.View do
  @moduledoc "Semantic widget composition for the console index."

  alias Tilde.Core.{Index, Widget}

  @spec widgets(Index.t()) :: [Widget.t()]
  def widgets(%Index{} = index) do
    [
      Widget.screen("index-screen", screen_widgets(index), metadata: %{class: "index"})
    ]
  end

  defp screen_widgets(%Index{} = index) do
    [
      Widget.text("index-title", "tilde", kind: :heading),
      sessions_widget(index),
      Widget.input("index-input", index.input),
      Widget.shortcut_bar("index-shortcuts", [
        %{key: "↑/↓", label: "select"},
        %{key: "enter", label: "open"},
        %{key: "n", label: "new"},
        %{key: "/", label: "command"}
      ]),
      Widget.footer("index-footer", right: "/new name · /attach name")
    ]
    |> List.flatten()
  end

  defp sessions_widget(%Index{command_suggest: command_suggest})
       when not is_nil(command_suggest) do
    Widget.new("command-suggestions", :above_input, command_suggest, kind: :suggest)
  end

  defp sessions_widget(%Index{session_suggest: nil}) do
    Widget.text("index-empty", "no sessions", kind: :muted)
  end

  defp sessions_widget(%Index{session_suggest: suggest}) do
    Widget.section("index-sessions", "sessions", [
      Widget.new("session-index", :above_input, suggest, kind: :suggest)
    ])
  end
end
