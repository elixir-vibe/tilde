defmodule Tilde.Transport.Live.ViewRenderer do
  @moduledoc """
  LiveView renderer for shared `Tilde.View.Cell` values.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.ChoiceBlock
  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Dialog
  import Tilde.Transport.Live.Line
  import Tilde.Transport.Live.Markdown
  import Tilde.Transport.Live.Run
  import Tilde.Transport.Live.SlashCommand
  import Tilde.Transport.Live.ToolBlock

  alias Tilde.View.Cell

  attr(:cell, Cell, required: true)

  def cell(%{cell: %Cell{kind: :message}} = assigns) do
    ~H"""
    <article class={["block", "message", @cell.role]} data-role={@cell.role}>
      <div class="label">{@cell.role}</div>
      <div class="body">
        <.runs :if={@cell.runs != []} runs={@cell.runs} />
        <.markdown :if={@cell.runs == [] and @cell.format == :markdown} source={@cell.source} />
        <%= if @cell.runs == [] and @cell.format != :markdown do %>
          {@cell.source}
        <% end %>
      </div>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :compaction}} = assigns) do
    assigns =
      assigns
      |> assign(:block, assigns.cell.attrs.block)
      |> assign(:tokens_before, compaction_tokens(assigns.cell.attrs.block))
      |> assign(:expanded?, assigns.cell.attrs.block.display.expanded?)

    ~H"""
    <article
      id={@cell.id}
      class="block compaction"
      data-block-id={@cell.id}
      data-expandable="true"
      data-expand-key="ctrl+o"
      tabindex="0"
    >
      <header class="header">
        <span class="label">[compaction]</span>
      </header>

      <div :if={!@expanded?} class="body muted">
        Compacted from {@tokens_before} tokens (<span class="key">ctrl+o</span> to expand)
      </div>

      <div :if={@expanded?} class="body">
        <div class="muted">Compacted from {@tokens_before} tokens</div>
        <.markdown source={@cell.source} />
      </div>

      <footer class="footer actions">
        <.action
          event="tilde:toggle_expand"
          label={if @expanded?, do: "collapse", else: "expand"}
          key={if @expanded?, do: nil, else: "ctrl+o"}
          values={%{"phx-value-id" => @cell.id}}
        />
      </footer>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :tool}} = assigns) do
    ~H"""
    <.tool_block cell={@cell} />
    """
  end

  def cell(%{cell: %Cell{kind: :choice}} = assigns) do
    ~H"""
    <.choice_block cell={@cell} />
    """
  end

  def cell(%{cell: %Cell{kind: :dialog}} = assigns) do
    assigns =
      assigns
      |> assign(:dialog, assigns.cell.attrs.dialog)
      |> assign(:widget, assigns.cell.attrs.widget)

    ~H"""
    <.dialog_widget id={@cell.id} dialog={@dialog} actions={@widget.actions} />
    """
  end

  def cell(%{cell: %Cell{kind: :suggest}} = assigns) do
    assigns = assign(assigns, :suggest, assigns.cell.attrs.suggest)

    ~H"""
    <section class="suggest" data-suggest-trigger={@suggest.trigger} data-suggest-query={@suggest.query}>
      <div class="title">{@suggest.title}</div>
      <div class="items">
        <.slash_command_button
          :for={{item, index} <- Enum.with_index(@suggest.items)}
          insert={item.insert}
          class={["row", index == @suggest.selected_index && "selected"]}
          aria-describedby={item.detail && "#{@suggest.id}-detail-#{index}"}
        >
          <span class="marker" aria-hidden="true">
            <%= if index == @suggest.selected_index, do: "›", else: "" %>
          </span>
          <code class="command">{item.label}</code>
          <span class="description">{item.description}</span>
          <span :if={item.detail} id={"#{@suggest.id}-detail-#{index}"} class="detail" role="tooltip">
            {item.detail}
          </span>
        </.slash_command_button>
      </div>
    </section>
    """
  end

  def cell(assigns) do
    ~H"""
    <%= for line <- @cell.lines do %>
      <div><.line line={line} /></div>
    <% end %>
    """
  end

  defp compaction_tokens(%{metadata: metadata}) do
    metadata
    |> Map.get(:tokens_before, 0)
    |> case do
      value when is_integer(value) -> Integer.to_string(value)
      value -> to_string(value)
    end
  end
end
