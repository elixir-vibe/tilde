defmodule Tilde.Transport.Live.SlashCommand do
  @moduledoc """
  Reusable slash-command input completion affordances.

  These components never submit commands directly. They insert command text into
  the console input through the shared `tilde:complete_input` event so every
  transport path keeps command execution behind the normal input/submit flow.
  """

  use Phoenix.Component

  attr(:label, :string, required: true)
  attr(:insert, :string, required: true)
  attr(:class, :any, default: "action normal")
  attr(:rest, :global)

  def slash_command(assigns) do
    ~H"""
    <a
      href="#"
      class={@class}
      phx-click="tilde:complete_input"
      phx-value-insert={@insert}
      {@rest}
    >{@label}</a>
    """
  end

  attr(:insert, :string, required: true)
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def slash_command_button(assigns) do
    ~H"""
    <button
      type="button"
      class={@class}
      phx-click="tilde:complete_input"
      phx-value-insert={@insert}
      {@rest}
    >{render_slot(@inner_block)}</button>
    """
  end

  attr(:commands, :list, required: true)
  attr(:class, :string, default: "actions")
  attr(:label, :string, default: "commands")
  attr(:separator, :string, default: " · ")
  attr(:rest, :global)

  def slash_commands(assigns) do
    ~H"""
    <span :if={@commands != []} class={@class} role="navigation" aria-label={@label} {@rest}>
      <%= for {command, index} <- Enum.with_index(@commands) do %>
        <.slash_command label={command.label} insert={command.insert} /><span :if={index < length(@commands) - 1}>{@separator}</span>
      <% end %>
    </span>
    """
  end
end
