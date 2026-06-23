defmodule Tilde.Transport.Live.Dialog do
  @moduledoc "Shared LiveView dialog component for Tilde surfaces."

  use Phoenix.Component

  alias Tilde.Core.{Action, Dialog}

  attr(:id, :string, required: true)
  attr(:title, :string, default: "")
  attr(:body, :string, default: "")
  attr(:modal?, :boolean, default: true)
  attr(:class, :any, default: nil)
  attr(:actions, :list, default: [])
  slot(:inner_block)
  slot(:action)

  def dialog(assigns) do
    assigns = assign(assigns, :classes, dialog_classes(assigns.class))

    ~H"""
    <section
      id={@id}
      class={@classes}
      role="dialog"
      aria-modal={@modal?}
      aria-labelledby={title_id(@id)}
    >
      <div :if={@title != ""} id={title_id(@id)} class="title">{@title}</div>
      <div class="body">
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@body}
        <% end %>
      </div>
      <div :if={@actions != [] or @action != []} class="actions">
        <.dialog_action :for={action <- @actions} action={action} />
        {render_slot(@action)}
      </div>
    </section>
    """
  end

  attr(:dialog, Dialog, required: true)
  attr(:id, :string, required: true)
  attr(:actions, :list, default: [])
  attr(:class, :any, default: nil)

  def dialog_widget(assigns) do
    ~H"""
    <.dialog
      id={@id}
      title={@dialog.title}
      body={@dialog.body}
      modal?={@dialog.modal?}
      actions={@actions}
      class={@class}
    />
    """
  end

  attr(:action, Action, required: true)

  defp dialog_action(assigns) do
    ~H"""
    <button type="button" class={["action", @action.kind]} {action_attrs(@action)}>
      <span :if={@action.key} class="key">{@action.key}</span>
      <span>{@action.label}</span>
    </button>
    """
  end

  defp title_id(id), do: id <> "-title"

  defp dialog_classes(class),
    do: ["dialog" | List.wrap(class)] |> Enum.reject(&(&1 in [nil, false, ""]))

  defp action_attrs(%Action{metadata: metadata}) do
    event = Map.get(metadata, :event)
    values = Map.get(metadata, :values, %{})

    %{}
    |> maybe_put("phx-click", event)
    |> Map.merge(value_attrs(values))
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp value_attrs(values) when is_map(values) do
    Map.new(values, fn {key, value} -> {"phx-value-#{key}", value} end)
  end

  defp value_attrs(_values), do: %{}
end
