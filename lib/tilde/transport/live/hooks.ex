defmodule Tilde.Transport.Live.Hooks do
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
          this.scroller = this.el.querySelector("#tilde-transcript")

          this.isNearBottom = () => {
            if (!this.scroller) return true
            return this.scroller.scrollTop + this.scroller.clientHeight >= this.scroller.scrollHeight - this.bottomThreshold
          }

          this.scrollToBottom = () => {
            if (!this.scroller) return
            this.scroller.scrollTop = this.scroller.scrollHeight
          }

          this.stickToBottom = () => {
            if (!this.shouldStickToBottom) return
            requestAnimationFrame(this.scrollToBottom)
          }

          this.resizeInput = (textarea) => {
            if (!textarea) return

            const previousValue = textarea.dataset.tildeLastValue || ""
            const currentHeight = textarea.getBoundingClientRect().height
            const growing = textarea.scrollHeight > currentHeight + 1
            const shrinking = textarea.value.length < previousValue.length

            if (growing || shrinking) {
              if (shrinking) textarea.style.height = "auto"
              const nextHeight = textarea.scrollHeight
              if (Math.abs(nextHeight - currentHeight) > 1) {
                textarea.style.height = `${nextHeight}px`
              }
            }

            textarea.dataset.tildeLastValue = textarea.value
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

          this.handleCompletion = ({ insert }) => {
            const textarea = this.el.querySelector("textarea[name='input']")
            if (!textarea || !insert) return
            textarea.value = insert
            this.resizeInput(textarea)
            textarea.focus()
          }

          this.handleEvent("tilde:input_completed", this.handleCompletion)

          this.handleKeydown = (event) => {
            const key = event.key && event.key.toLowerCase()
            const target = event.target

            if (target && target.matches && target.matches("textarea[name='input']")) {
              if (key === "tab" && target.value.trimStart().startsWith("/")) {
                event.preventDefault()
                const firstSuggestion = this.el.querySelector(".tilde-suggest-row[phx-value-insert]")
                const insert = firstSuggestion && firstSuggestion.getAttribute("phx-value-insert")
                if (insert) {
                  target.value = insert
                  this.resizeInput(target)
                  this.pushEvent("tilde:complete_input", { insert })
                } else {
                  this.pushEvent("tilde:complete_input", { input: target.value })
                }
                return
              }

              if (key === "enter") {
                if (event.shiftKey) return

                event.preventDefault()
                this.shouldStickToBottom = true
                target.form && target.form.requestSubmit()
                return
              }
            }

            if (!event.ctrlKey || key !== "o") return

            const active = document.activeElement
            const focusedBlock = active && active.closest && active.closest(".tilde-tool[data-block-id]")
            const block = this.el.contains(focusedBlock) ? focusedBlock : this.el.querySelector(".tilde-tool[data-block-id]")
            if (!block) return

            event.preventDefault()
            this.pushEvent("tilde:toggle_expand", { id: block.dataset.blockId })
          }

          this.scroller && this.scroller.addEventListener("scroll", this.handleScroll, { passive: true })
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
          this.scroller && this.scroller.removeEventListener("scroll", this.handleScroll)
          this.el.removeEventListener("submit", this.handleSubmit)
          this.el.removeEventListener("input", this.handleInput)
          this.el.removeEventListener("keydown", this.handleKeydown)
        }
      }
    }
    """
  end
end
