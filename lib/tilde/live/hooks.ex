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
          this.shouldStickToBottom = true
          this.bottomThreshold = 80

          this.isNearBottom = () => {
            const doc = document.documentElement
            return window.innerHeight + window.scrollY >= doc.scrollHeight - this.bottomThreshold
          }

          this.scrollToBottom = () => {
            window.scrollTo({ top: document.documentElement.scrollHeight })
          }

          this.stickToBottom = () => {
            if (!this.shouldStickToBottom) return
            requestAnimationFrame(this.scrollToBottom)
          }

          this.resizeInput = (textarea) => {
            if (!textarea) return
            textarea.style.height = "auto"
            textarea.style.height = `${textarea.scrollHeight}px`
          }

          this.resizeCurrentInput = () => this.resizeInput(this.el.querySelector("textarea[name='input']"))

          this.handleScroll = () => {
            this.shouldStickToBottom = this.isNearBottom()
          }

          this.handleSubmit = () => {
            this.shouldStickToBottom = true
          }

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
              this.shouldStickToBottom = true
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

          window.addEventListener("scroll", this.handleScroll, { passive: true })
          this.el.addEventListener("submit", this.handleSubmit)
          this.el.addEventListener("input", this.handleInput)
          this.el.addEventListener("keydown", this.handleKeydown)
          this.resizeCurrentInput()
          this.stickToBottom()
        },

        updated() {
          this.resizeCurrentInput()
          this.stickToBottom()
        },

        destroyed() {
          window.removeEventListener("scroll", this.handleScroll)
          this.el.removeEventListener("submit", this.handleSubmit)
          this.el.removeEventListener("input", this.handleInput)
          this.el.removeEventListener("keydown", this.handleKeydown)
        }
      }
    }
    """
  end
end
