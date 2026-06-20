defmodule Tilde.Demo.PlaygroundLive do
  @moduledoc "Design playground for future semantic web components."

  use Phoenix.LiveView

  import Tilde.Transport.Live.Block
  import Tilde.Transport.Live.Footer

  alias Tilde.Core.{Interaction, Session}
  alias Tilde.Demo.Playground.Fixtures
  alias Tilde.Transport.Live.Interaction, as: LiveInteraction

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       sections: Fixtures.sections(),
       devtools?: false,
       dev_grid?: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["devshell", @dev_grid? && "grid"]} data-dev-grid={@dev_grid?}>
      <main id="tilde-playground-console" class="tilde playground" phx-hook="TildeConsole">
        <section class="transcript playground-sections" id="tilde-transcript">
          <header class="playground-header">
            <p class="eyebrow">design playground</p>
            <h1>Semantic component fixtures</h1>
            <p>
              Static sessions rendered through the real LiveView block/component pipeline.
              These fixtures expose pressure for future reusable web components.
            </p>
          </header>

          <article :for={section <- @sections} id={"playground-#{section.id}"} class="playground-section">
            <header class="playground-section-header">
              <p class="eyebrow">{section.id}</p>
              <h2>{section.title}</h2>
              <p>{section.description}</p>
            </header>

            <section class="playground-frame transcript">
              <.block :for={block <- section.session.transcript.blocks} block={block} />
            </section>
          </article>
        </section>

        <section class="dock playground-dock">
          <.footer
            session={nil}
            right="/playground"
            devtools?={@devtools?}
            dev_grid?={@dev_grid?}
            dev_raw=""
          />
        </section>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event(event, params, socket) do
    case LiveInteraction.session(event, params) do
      %Interaction{} = interaction -> apply_interaction(socket, interaction)
      nil -> {:noreply, socket}
    end
  end

  defp apply_interaction(socket, %Interaction{type: :toggle_expand, payload: %{id: block_id}}) do
    {:noreply,
     update(
       socket,
       :sections,
       &update_section_session(&1, block_id, fn session ->
         Session.toggle_expand(session, block_id)
       end)
     )}
  end

  defp apply_interaction(socket, %Interaction{type: :toggle_expand}) do
    {:noreply,
     update(socket, :sections, fn sections ->
       Enum.map(sections, &%{&1 | session: Session.toggle_tool_expansion(&1.session)})
     end)}
  end

  defp apply_interaction(socket, %Interaction{
         type: :select_choice,
         payload: %{block_id: block_id, option_id: option_id}
       }) do
    {:noreply,
     update(
       socket,
       :sections,
       &update_section_session(&1, block_id, fn session ->
         Session.select_choice(session, block_id, option_id)
       end)
     )}
  end

  defp apply_interaction(socket, %Interaction{}), do: {:noreply, socket}

  defp update_section_session(sections, block_id, fun) do
    Enum.map(sections, fn section ->
      if has_block?(section.session, block_id) do
        %{section | session: fun.(section.session)}
      else
        section
      end
    end)
  end

  defp has_block?(session, block_id) do
    Enum.any?(session.transcript.blocks, &(&1.id == block_id))
  end
end
