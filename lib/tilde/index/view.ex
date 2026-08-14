defmodule Tilde.Index.View do
  @moduledoc "Semantic widget composition for the console index."

  alias Tilde.Index

  @shortcuts [
    %{key: "↑/↓", label: "select"},
    %{key: "enter", label: "open"},
    %{key: "n", label: "new"},
    %{key: "/", label: "command"}
  ]

  @spec widgets(Index.t()) :: [Tilde.Core.Widget.t()]
  def widgets(%Index{} = index) do
    require Tilde.Template

    Tilde.Template.to_widgets!(template(index),
      assigns: %{
        input: index.input,
        shortcuts: @shortcuts,
        suggest: index.command_suggest || index.session_suggest,
        suggest_id: if(index.command_suggest, do: "command-suggestions", else: "session-index"),
        footer_commands: footer_commands()
      }
    )
  end

  defp template(%Index{command_suggest: nil, session_suggest: nil}) do
    """
    <.screen id="tilde-console" class="index">
      <.widget_text id="index-title" text="tilde" kind="heading" />
      <.widget_text id="index-empty" text="no sessions" kind="muted" />
      <.widget_input id="index-input" input={@input} />
      <.shortcut_bar id="index-shortcuts" shortcuts={@shortcuts} />
      <.widget_footer id="index-footer" commands={@footer_commands} />
    </.screen>
    """
  end

  defp template(%Index{}) do
    """
    <.screen id="tilde-console" class="index">
      <.widget_text id="index-title" text="tilde" kind="heading" />
      <.section id="index-sessions" title="sessions">
        <.widget_suggest id={@suggest_id} suggest={@suggest} />
      </.section>
      <.widget_input id="index-input" input={@input} />
      <.shortcut_bar id="index-shortcuts" shortcuts={@shortcuts} />
      <.widget_footer id="index-footer" commands={@footer_commands} />
    </.screen>
    """
  end

  defp footer_commands do
    labels = ["/help", "/showcase", "/new"]
    specs_by_label = Map.new(Tilde.Command.Registry.specs(), &{&1.label, &1})

    Enum.map(labels, &Map.fetch!(specs_by_label, &1))
  end
end
