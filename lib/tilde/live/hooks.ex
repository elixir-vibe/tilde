defmodule Tilde.Live.Hooks do
  @moduledoc """
  JavaScript hooks for Tilde Live components.

  Host Phoenix apps can copy `js/0` into their assets or adapt the hook body to
  their existing LiveSocket setup. The semantic fallback remains click-based, so
  hooks only add keyboard affordances such as focused-block `ctrl+o` expansion.
  """

  @doc "Returns the default Tilde LiveView hook JavaScript."
  @spec js() :: String.t()
  def js do
    """
    export const TildeHooks = {
      TildeConsole: {
        mounted() {
          this.handleKeydown = (event) => {
            const key = event.key && event.key.toLowerCase()
            if (!event.ctrlKey || key !== "o") return

            const active = document.activeElement
            const block = active && active.closest && active.closest("[data-block-id]")
            if (!block || !this.el.contains(block)) return

            event.preventDefault()
            this.pushEvent("tilde:toggle_expand", { id: block.dataset.blockId })
          }

          this.el.addEventListener("keydown", this.handleKeydown)
        },

        destroyed() {
          this.el.removeEventListener("keydown", this.handleKeydown)
        }
      }
    }
    """
  end
end
