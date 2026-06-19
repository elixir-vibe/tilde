import { autoUpdate, computePosition, flip, offset, shift } from "@floating-ui/dom"

const TildeDevtools = {
  mounted() {
    const root = this.el as HTMLElement
    const button = root.querySelector<HTMLElement>(".button")
    const tooltip = root.querySelector<HTMLElement>(".tooltip")
    let cleanup: (() => void) | undefined

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

    const show = () => {
      tooltip.textContent = tooltip.dataset.raw ?? ""
      document.body.appendChild(tooltip)
      Object.assign(tooltip.style, {
        position: "fixed",
        zIndex: "60",
        width: "min(56ch, calc(100vw - 48px))",
        maxHeight: "14rem",
        overflow: "auto",
        margin: "0",
        border: "1px solid var(--color-border)",
        padding: "var(--space-xs) 1ch",
        background: "var(--color-bg)",
        color: "var(--color-fg)",
        font: "inherit",
        whiteSpace: "pre",
        pointerEvents: "none",
        visibility: "visible"
      })
      tooltip.dataset.open = "true"
      cleanup = autoUpdate(button, tooltip, update)
      update()
    }

    const hide = () => {
      delete tooltip.dataset.open
      tooltip.textContent = ""
      tooltip.style.visibility = "hidden"
      root.appendChild(tooltip)
      cleanup?.()
      cleanup = undefined
    }

    button.addEventListener("mouseenter", show)
    button.addEventListener("mouseleave", hide)
    button.addEventListener("mouseover", show)
    button.addEventListener("mouseout", hide)

    this.cleanupDevtools = () => {
      hide()
      button.removeEventListener("mouseenter", show)
      button.removeEventListener("mouseleave", hide)
      button.removeEventListener("mouseover", show)
      button.removeEventListener("mouseout", hide)
    }
  },

  destroyed() {
    this.cleanupDevtools?.()
  }
}

export default TildeDevtools
