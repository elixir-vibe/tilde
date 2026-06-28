defmodule Tilde.Transport.Live.Palette do
  @moduledoc "LiveView component for Tilde's command palette."

  use Phoenix.Component

  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Dialog

  alias Tilde.Core.Palette
  alias Tilde.Core.Palette.Item

  attr(:palette, Palette, required: true)

  def palette(assigns) do
    ~H"""
    <div :if={@palette.open?} class="palette-layer">
      <.dialog id="tilde-palette" title={palette_title(@palette)} class="palette" modal?={true}>
        <nav class="modes actions" aria-label="palette modes">
          <.action
            :for={action <- mode_actions()}
            event="tilde:palette:mode"
            label={action.label}
            shortcut={action.shortcut}
            kind={mode_kind(@palette.mode, action.mode)}
            values={%{"phx-value-mode" => Atom.to_string(action.mode)}}
          />
        </nav>
        <form class="input" phx-change="tilde:palette:change" phx-submit="tilde:palette:accept">
          <input
            id="tilde-palette-query"
            name="query"
            value={@palette.query}
            autocomplete="off"
            autofocus
            aria-label="file palette query"
            phx-hook="TildePaletteInput"
          />
        </form>

        <div class="choices" role="listbox" aria-label="palette results">
          <button
            :for={{item, index} <- Enum.with_index(@palette.items)}
            type="button"
            class={choice_classes(index, @palette.selected_index)}
            role="option"
            aria-selected={index == @palette.selected_index}
            phx-click="tilde:palette:select"
            phx-value-index={index}
          >
            <span class="label">{item.label}</span>
            <span class="detail">{item_detail(item)}</span>
          </button>
          <div :if={@palette.items == []} class="choice empty" role="option" aria-disabled="true">
            <span class="label">{empty_label(@palette)}</span>
            <span class="detail">{empty_detail(@palette)}</span>
          </div>
        </div>
      </.dialog>
    </div>
    """
  end

  defp palette_title(%Palette{mode: :symbols}), do: "jump to symbol"
  defp palette_title(%Palette{}), do: "open file"

  defp mode_actions do
    [
      %{mode: :files, label: "files", shortcut: "tilde.palette.mode_files"},
      %{mode: :symbols, label: "symbols", shortcut: "tilde.palette.mode_symbols"}
    ]
  end

  defp mode_kind(mode, mode), do: :selected
  defp mode_kind(_active_mode, _mode), do: :normal

  defp choice_classes(index, selected_index),
    do: ["choice", index == selected_index && "selected"]

  defp empty_label(%Palette{mode: :symbols}), do: "No matching symbols."
  defp empty_label(%Palette{}), do: "No matching files."

  defp empty_detail(%Palette{mode: :symbols}), do: "Open a file first or change the query."
  defp empty_detail(%Palette{}), do: "Only session and changed files are searched."

  defp item_detail(%Item{detail: nil}), do: ""
  defp item_detail(%Item{detail: detail}), do: detail
end
