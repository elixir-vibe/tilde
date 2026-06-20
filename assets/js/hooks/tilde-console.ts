import type { ViewHook } from "phoenix_live_view"

type TildeConsoleHook = ViewHook & {
  scroller?: HTMLElement | null
  shouldStickToBottom?: boolean
  bottomThreshold?: number
  isNearBottom?: () => boolean
  scrollToBottom?: () => void
  stickToBottom?: () => void
  resizeInput?: (textarea: HTMLTextAreaElement | null) => void
  resizeCurrentInput?: () => void
  handleScroll?: () => void
  handleSubmit?: () => void
  handleInput?: (event: Event) => void
  handleCompletion?: (payload: { insert?: string }) => void
  handleKeydown?: (event: KeyboardEvent) => void
}

const inputSelector = "textarea[name='input']"

const TildeConsole: Partial<TildeConsoleHook> = {
  mounted() {
    this.shouldStickToBottom = true
    this.bottomThreshold = 80
    this.scroller = this.el.querySelector("#tilde-transcript")

    this.isNearBottom = () => {
      if (!this.scroller) return true

      return (
        this.scroller.scrollTop + this.scroller.clientHeight >=
        this.scroller.scrollHeight - (this.bottomThreshold || 0)
      )
    }

    this.scrollToBottom = () => {
      if (!this.scroller) return
      this.scroller.scrollTop = this.scroller.scrollHeight
    }

    this.stickToBottom = () => {
      if (!this.shouldStickToBottom || !this.scrollToBottom) return
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

    this.resizeCurrentInput = () => {
      this.resizeInput?.(this.el.querySelector(inputSelector))
    }

    this.handleScroll = () => {
      this.shouldStickToBottom = this.isNearBottom?.() || false
    }

    this.handleSubmit = () => {
      this.shouldStickToBottom = true
    }

    this.handleInput = (event) => {
      const target = event.target
      if (target instanceof HTMLTextAreaElement && target.matches(inputSelector)) {
        this.resizeInput?.(target)
      }
    }

    this.handleCompletion = ({ insert }) => {
      const textarea = this.el.querySelector(inputSelector)
      if (!(textarea instanceof HTMLTextAreaElement) || insert === undefined) return

      textarea.value = insert
      this.resizeInput?.(textarea)
      textarea.focus()
    }

    this.handleEvent("tilde:input_completed", this.handleCompletion)

    this.handleKeydown = (event) => {
      const key = event.key && event.key.toLowerCase()
      const target = event.target

      if (
        target instanceof HTMLTextAreaElement &&
        target.matches(inputSelector) &&
        this.el.contains(target)
      ) {
        const suggestions = this.el.querySelector(".suggest")

        if (
          this.el.classList.contains("index") &&
          !suggestions &&
          key === "n" &&
          target.value === ""
        ) {
          event.preventDefault()
          this.pushEvent("tilde:index_new", {})
          return
        }

        if (suggestions && (key === "arrowdown" || (event.ctrlKey && key === "n"))) {
          event.preventDefault()
          this.pushEvent("tilde:suggest_next", {})
          return
        }

        if (suggestions && (key === "arrowup" || (event.ctrlKey && key === "p"))) {
          event.preventDefault()
          this.pushEvent("tilde:suggest_previous", {})
          return
        }

        if (suggestions && key === "escape") {
          event.preventDefault()
          this.pushEvent("tilde:suggest_cancel", {})
          return
        }

        if (key === "tab" && target.value.trimStart().startsWith("/")) {
          event.preventDefault()
          this.pushEvent("tilde:suggest_accept", {})
          return
        }

        if (key === "enter") {
          if (event.shiftKey) return

          event.preventDefault()
          this.shouldStickToBottom = true

          if (suggestions) {
            this.pushEvent("tilde:suggest_submit", {})
          } else {
            target.form?.requestSubmit()
          }

          return
        }
      }

      const globalEvent = event as KeyboardEvent & { tildeHandled?: boolean }
      if (globalEvent.tildeHandled || !event.ctrlKey || key !== "o") return

      event.preventDefault()
      globalEvent.tildeHandled = true
      this.pushEvent("tilde:toggle_expand", {})
    }

    this.scroller?.addEventListener("scroll", this.handleScroll, { passive: true })
    this.el.addEventListener("submit", this.handleSubmit)
    this.el.addEventListener("input", this.handleInput)
    document.addEventListener("keydown", this.handleKeydown, { capture: true })
    this.resizeCurrentInput()
    this.stickToBottom?.()
  },

  updated() {
    this.resizeCurrentInput?.()
    this.stickToBottom?.()
  },

  destroyed() {
    if (this.handleScroll) this.scroller?.removeEventListener("scroll", this.handleScroll)
    if (this.handleSubmit) this.el.removeEventListener("submit", this.handleSubmit)
    if (this.handleInput) this.el.removeEventListener("input", this.handleInput)
    if (this.handleKeydown)
      document.removeEventListener("keydown", this.handleKeydown, { capture: true })
  }
}

export default TildeConsole
