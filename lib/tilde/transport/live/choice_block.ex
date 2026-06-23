defmodule Tilde.Transport.Live.ChoiceBlock do
  @moduledoc """
  LiveView renderer for choice cells using the shared panel anatomy.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Line
  import Tilde.Transport.Live.Panel

  alias Tilde.View.{Cell, Helpers}

  attr(:cell, Cell, required: true)

  def choice_block(assigns) do
    assigns =
      assigns
      |> assign(:choice, assigns.cell.attrs.choice)
      |> assign(:heading, List.first(assigns.cell.lines) || Helpers.line(""))

    ~H"""
    <.panel id={@cell.id} kind="choice">
      <:header>
        <span class="call"><.line line={@heading} /></span>
      </:header>

      <:body>
        <div class="options">
          <button
            :for={option <- @choice.options}
            type="button"
            class={["option", option.id in @choice.selected && "selected"]}
            phx-click="tilde:select_choice"
            phx-value-block-id={@cell.id}
            phx-value-option-id={option.id}
          >
            <span class="marker">{if option.id in @choice.selected, do: "[x]", else: "[ ]"}</span>
            <span>{option.label}</span>
            <span :if={option[:description]} class="description">— {option.description}</span>
          </button>
        </div>
      </:body>

      <:footer>
        <.action
          :for={action <- @choice.actions}
          event="tilde:choice_action"
          label={action.label}
          key={action.key}
          kind={action.kind}
          values={%{"phx-value-block-id" => @cell.id, "phx-value-action-id" => action.id}}
        />
      </:footer>
    </.panel>
    """
  end
end
