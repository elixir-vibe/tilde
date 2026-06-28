import type { ViewHook } from "phoenix_live_view"

type WorkspaceFileHook = ViewHook & {
  scrollToRequestedLine?: () => void
}

const WorkspaceFile: Partial<WorkspaceFileHook> = {
  mounted() {
    this.scrollToRequestedLine?.()
  },

  updated() {
    this.scrollToRequestedLine?.()
  },

  scrollToRequestedLine() {
    const root = this.el as HTMLElement
    const line = root.dataset.scrollLine
    if (!line) return

    const body = root.querySelector<HTMLElement>(".body")
    const target = body?.querySelector<HTMLElement>(`.l-line[data-line="${CSS.escape(line)}"]`)
    if (!body || !target) return

    target.scrollIntoView({ block: "center", inline: "nearest" })
  }
}

export default WorkspaceFile
