defmodule Tilde.Live.DemoLayout do
  @moduledoc """
  Root layout for `Tilde.Live.DemoEndpoint`.
  """

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :live_socket_js, live_socket_js())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Tilde demo</title>
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js">
        </script>
        <script src="/assets/live_view/phoenix_live_view.min.js">
        </script>
        {Phoenix.HTML.raw("<script>" <> @live_socket_js <> "</script>")}
      </body>
    </html>
    """
  end

  defp live_socket_js do
    """
    const TildeHooks = {
      TildeConsole: {
        mounted() {
          this.resizeInput = (textarea) => {
            if (!textarea) return
            textarea.style.height = "auto"
            textarea.style.height = `${textarea.scrollHeight}px`
          }

          this.resizeCurrentInput = () => this.resizeInput(this.el.querySelector("textarea[name='input']"))

          this.handleInput = (event) => {
            if (event.target && event.target.matches && event.target.matches("textarea[name='input']")) {
              this.resizeInput(event.target)
            }
          }

          this.handleKeydown = (event) => {
            const key = event.key && event.key.toLowerCase()
            const target = event.target

            if (target && target.matches && target.matches("textarea[name='input']") && key === "enter") {
              if (event.shiftKey) return

              event.preventDefault()
              target.form && target.form.requestSubmit()
              return
            }

            if (!event.ctrlKey || key !== "o") return

            const active = document.activeElement
            const focusedBlock = active && active.closest && active.closest(".tilde-tool[data-block-id]")
            const block = this.el.contains(focusedBlock) ? focusedBlock : this.el.querySelector(".tilde-tool[data-block-id]")
            if (!block) return

            event.preventDefault()
            this.pushEvent("tilde:toggle_expand", { id: block.dataset.blockId })
          }

          this.el.addEventListener("input", this.handleInput)
          this.el.addEventListener("keydown", this.handleKeydown)
          this.resizeCurrentInput()
        },

        updated() {
          this.resizeCurrentInput()
        },

        destroyed() {
          this.el.removeEventListener("input", this.handleInput)
          this.el.removeEventListener("keydown", this.handleKeydown)
        }
      }
    }

    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
      hooks: TildeHooks,
      params: { _csrf_token: csrfToken }
    })

    liveSocket.connect()
    window.liveSocket = liveSocket
    """
  end
end
