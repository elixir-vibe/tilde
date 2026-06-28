import { autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"
import type { ViewHook } from "phoenix_live_view"

type DevtoolsHook = ViewHook & {
  cleanupDevtools?: () => void
}

const closeDelayMs = 120

const Devtools: Partial<DevtoolsHook> = {
  mounted() {
    const root = this.el as HTMLElement
    const button = root.querySelector<HTMLElement>(".button")
    const tooltip = root.querySelector<HTMLElement>(".tooltip")
    let cleanup: (() => void) | undefined
    let closeTimer: number | undefined

    if (!button || !tooltip) return

    const update = () => {
      computePosition(button, tooltip, {
        placement: "top-end",
        strategy: "fixed",
        middleware: [offset(6), flip(), shift({ padding: 8 })]
      }).then(({ x, y }) => {
        Object.assign(tooltip.style, {
          left: `${x}px`,
          top: `${y}px`
        })
      })
    }

    const cancelClose = () => {
      if (closeTimer === undefined) return
      window.clearTimeout(closeTimer)
      closeTimer = undefined
    }

    const show = () => {
      cancelClose()
      tooltip.textContent = tooltip.dataset.raw ?? ""
      Object.assign(tooltip.style, {
        position: "fixed",
        zIndex: "60",
        display: "block",
        boxSizing: "border-box",
        width: "min(56ch, calc(100vw - 48px))",
        height: "min(14rem, calc(100vh - 48px))",
        overflow: "auto",
        margin: "0",
        border: "1px solid var(--color-border)",
        padding: "var(--space-xs) 1ch",
        background: "var(--color-bg)",
        color: "var(--color-fg)",
        font: "inherit",
        whiteSpace: "pre",
        pointerEvents: "auto",
        visibility: "visible"
      })
      tooltip.dataset.open = "true"
      cleanup ??= autoUpdate(button, tooltip, update)
      update()
    }

    const hide = () => {
      cancelClose()
      delete tooltip.dataset.open
      tooltip.textContent = ""
      tooltip.style.visibility = "hidden"
      cleanup?.()
      cleanup = undefined
    }

    const scheduleHide = () => {
      cancelClose()
      closeTimer = window.setTimeout(() => {
        closeTimer = undefined

        if (button.matches(":hover") || tooltip.matches(":hover")) return
        if (document.activeElement === button || document.activeElement === tooltip) return

        hide()
      }, closeDelayMs)
    }

    button.addEventListener("pointerenter", show)
    button.addEventListener("pointerleave", scheduleHide)
    button.addEventListener("focus", show)
    button.addEventListener("blur", scheduleHide)
    tooltip.addEventListener("pointerenter", show)
    tooltip.addEventListener("pointerleave", scheduleHide)
    tooltip.addEventListener("focusin", show)
    tooltip.addEventListener("focusout", scheduleHide)

    this.cleanupDevtools = () => {
      hide()
      button.removeEventListener("pointerenter", show)
      button.removeEventListener("pointerleave", scheduleHide)
      button.removeEventListener("focus", show)
      button.removeEventListener("blur", scheduleHide)
      tooltip.removeEventListener("pointerenter", show)
      tooltip.removeEventListener("pointerleave", scheduleHide)
      tooltip.removeEventListener("focusin", show)
      tooltip.removeEventListener("focusout", scheduleHide)
    }
  },

  destroyed() {
    this.cleanupDevtools?.()
  }
}

export default Devtools
