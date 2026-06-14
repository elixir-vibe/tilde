defmodule Tilde.Live.Choice do
  @moduledoc """
  LiveView component for semantic choice blocks.
  """

  use Phoenix.Component

  import Tilde.Live.Shortcut

  attr(:block, :any, required: true)
  attr(:select_event, :string, default: "tilde:select_choice")
  attr(:action_event, :string, default: "tilde:choice_action")

  def choice(assigns) do
    assigns = assign(assigns, :choice, assigns.block.choice)

    ~H"""
    <article id={@block.id} class="tilde-block tilde-choice" data-block-id={@block.id} tabindex="0">
      <div class="tilde-choice-question">{@choice.question}</div>

      <div class="tilde-choice-options">
        <button
          :for={option <- @choice.options}
          type="button"
          class={["tilde-choice-option", selected?(@choice, option.id) && "is-selected"]}
          phx-click={@select_event}
          phx-value-block-id={@block.id}
          phx-value-option-id={option.id}
        >
          <span class="tilde-choice-marker">{if selected?(@choice, option.id), do: "[x]", else: "[ ]"}</span>
          <span class="tilde-choice-label">{option.label}</span>
          <span :if={Map.get(option, :description)} class="tilde-choice-description">
            {option.description}
          </span>
        </button>
      </div>

      <footer class="tilde-choice-actions">
        <button
          :for={action <- @choice.actions}
          type="button"
          class={["tilde-action", "tilde-action-#{action.kind}"]}
          phx-click={@action_event}
          phx-value-block-id={@block.id}
          phx-value-action-id={action.id}
        >
          {action.label}<.shortcut :if={action.key} key={action.key} />
        </button>
      </footer>
    </article>
    """
  end

  defp selected?(choice, option_id), do: option_id in choice.selected
end
