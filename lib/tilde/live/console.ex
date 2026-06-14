defmodule Tilde.Live.Console do
  @moduledoc """
  LiveView component for a complete semantic console shell.

  The component renders DOM from `Tilde.Session`/`Tilde.Transcript` state. It does
  not own the semantic model and does not emulate a terminal.
  """

  use Phoenix.Component

  import Tilde.Live.Block
  import Tilde.Live.Footer
  import Tilde.Live.Input
  import Tilde.Live.ViewRenderer

  alias Tilde.{Session, Transcript}
  alias Tilde.View.Builder

  attr(:id, :string, default: "tilde-console")
  attr(:session, :any, default: nil)
  attr(:transcript, :any, default: nil)
  attr(:input, :string, default: "")
  attr(:running?, :boolean, default: false)
  attr(:class, :any, default: nil)
  attr(:footer_right, :string, default: "")

  def console(assigns) do
    assigns =
      assigns
      |> assign(:transcript, transcript(assigns))
      |> assign(:above_widgets, widgets(assigns.session, :above_input))
      |> assign(:below_widgets, widgets(assigns.session, :below_input))

    ~H"""
    <main id={@id} class={["tilde-console", @class]} phx-hook="TildeConsole">
      <section class="tilde-transcript" id="tilde-transcript">
        <.block :for={block <- @transcript.blocks} block={block} />
      </section>

      <section :if={@above_widgets != []} class="tilde-widgets tilde-widgets-above">
        <.widget :for={widget <- @above_widgets} widget={widget} />
      </section>

      <section class="tilde-dock">
        <.input value={@input} running?={@running?} />

        <section :if={@below_widgets != []} class="tilde-widgets tilde-widgets-below">
          <.widget :for={widget <- @below_widgets} widget={widget} />
        </section>

        <.footer session={@session} right={@footer_right} />
      </section>
    </main>
    """
  end

  attr(:widget, :any, required: true)

  def widget(assigns) do
    ~H"""
    <aside id={@widget.id} class={["tilde-widget", "tilde-widget-#{@widget.placement}"]}>
      <.cell cell={Builder.widget(@widget)} />
    </aside>
    """
  end

  defp transcript(%{transcript: %Transcript{} = transcript}), do: transcript
  defp transcript(%{session: %Session{transcript: transcript}}), do: transcript
  defp transcript(_assigns), do: Transcript.new()

  defp widgets(%Session{} = session, placement), do: Session.widgets(session, placement)
  defp widgets(_session, _placement), do: []
end
