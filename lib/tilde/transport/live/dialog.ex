defmodule Tilde.Transport.Live.Dialog do
  @moduledoc "Shared LiveView dialog component for Tilde surfaces."

  use Phoenix.Component

  import Tilde.Transport.Live.Controls

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
        <.dialog_action :for={action <- @actions} action={action} widget_id={@id} />
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
  attr(:widget_id, :string, required: true)

  defp dialog_action(assigns) do
    assigns =
      assigns
      |> assign(:event, action_event(assigns.action))
      |> assign(:values, action_values(assigns.action, assigns.widget_id))

    ~H"""
    <.action event={@event} label={@action.label} key={@action.key} kind={@action.kind} values={@values} />
    """
  end

  defp title_id(id), do: id <> "-title"

  defp dialog_classes(class),
    do: ["dialog" | List.wrap(class)] |> Enum.reject(&(&1 in [nil, false, ""]))

  defp action_event(%Action{metadata: metadata}),
    do: Map.get(metadata, :event, "tilde:dialog_action")

  defp action_values(%Action{metadata: metadata} = action, widget_id) do
    metadata
    |> Map.get(:values, %{})
    |> value_attrs()
    |> Map.put_new("phx-value-widget-id", widget_id)
    |> Map.put_new("phx-value-action-id", to_string(action.id))
    |> maybe_put_key(action.key)
  end

  defp maybe_put_key(attrs, nil), do: attrs
  defp maybe_put_key(attrs, key), do: Map.put_new(attrs, "data-key", key)

  defp value_attrs(values) when is_map(values) do
    Map.new(values, fn {key, value} -> {"phx-value-#{key}", value} end)
  end

  defp value_attrs(_values), do: %{}
end
