defmodule Tilde.Transport.Live.Console do
  @moduledoc """
  LiveView component for a complete semantic console shell.

  The component renders DOM from `Tilde.Core.Session`/`Tilde.Core.Transcript` state. It does
  not own the semantic model and does not emulate a terminal.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Block
  import Tilde.Transport.Live.Footer
  import Tilde.Transport.Live.Input
  import Tilde.Transport.Live.ViewRenderer

  alias Tilde.Core.{Session, Transcript}

  attr(:id, :string, default: "tilde-console")
  attr(:session, :any, default: nil)
  attr(:transcript, :any, default: nil)
  attr(:input, :string, default: "")
  attr(:running?, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:footer_right, :string, default: "")
  attr(:devtools?, :boolean, default: false)
  attr(:dev_grid?, :boolean, default: false)
  attr(:dev_raw, :string, default: "")

  def console(assigns) do
    assigns =
      assigns
      |> assign(:transcript, transcript(assigns))
      |> assign(:above_widgets, widgets(assigns.session, :above_input))
      |> assign(:below_widgets, widgets(assigns.session, :below_input))
      |> assign(:pending?, pending?(assigns.session))

    ~H"""
    <main id={@id} class={["tilde", @class]} phx-hook="TildeConsole">
      <section class="transcript" id="tilde-transcript">
        <.block :for={block <- @transcript.blocks} block={block} />
        <article :if={@pending?} class="block message assistant pending" data-role="assistant" aria-live="polite">
          <div class="label">assistant</div>
          <div class="body muted">thinking…</div>
        </article>
      </section>

      <section :if={@above_widgets != []} class="widgets" data-placement="above_input">
        <.widget :for={widget <- @above_widgets} widget={widget} />
      </section>

      <section class="dock">
        <.input value={@input} running?={@running? or @pending?} />

        <section :if={@below_widgets != []} class="widgets" data-placement="below_input">
          <.widget :for={widget <- @below_widgets} widget={widget} />
        </section>

        <.footer
          session={@session}
          right={@footer_right}
          devtools?={@devtools?}
          dev_grid?={@dev_grid?}
          dev_raw={@dev_raw}
        />
      </section>
    </main>
    """
  end

  attr(:widget, :any, required: true)

  def widget(assigns) do
    ~H"""
    <aside id={@widget.id} class="widget" data-placement={@widget.placement}>
      <.cell cell={Tilde.Viewable.to_view(@widget)} />
    </aside>
    """
  end

  defp transcript(%{transcript: %Transcript{} = transcript}), do: transcript
  defp transcript(%{session: %Session{transcript: transcript}}), do: transcript
  defp transcript(_assigns), do: Transcript.new()

  defp widgets(%Session{} = session, placement), do: Session.widgets(session, placement)
  defp widgets(_session, _placement), do: []

  defp pending?(%Session{} = session), do: Session.assistant_waiting?(session)
  defp pending?(_session), do: false
end
