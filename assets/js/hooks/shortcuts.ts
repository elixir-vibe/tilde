import type { ViewHook } from "phoenix_live_view"

type ShortcutBinding = {
  id: string
  keys: string[]
  scopes: string[]
  preventDefault?: boolean
  captureInteractive?: boolean
}

type ShortcutsHook = ViewHook & {
  handleShortcutKeydown?: (event: KeyboardEvent) => void
}

const interactiveSelector =
  "textarea,input,select,button,a,[contenteditable=''],[contenteditable='true']"

function isInteractiveTarget(target: EventTarget | null): boolean {
  return target instanceof Element && target.closest(interactiveSelector) !== null
}

function normalizedKey(event: KeyboardEvent): string | null {
  const key = normalizedBaseKey(event)
  if (!key) return null

  const modifiers = []
  if (event.ctrlKey) modifiers.push("ctrl")
  if (event.metaKey) modifiers.push("meta")
  if (event.altKey) modifiers.push("alt")
  if (event.shiftKey) modifiers.push("shift")

  return [...modifiers, key].join("+")
}

function normalizedBaseKey(event: KeyboardEvent): string | null {
  if (event.key.length === 1) return event.key.toLowerCase()
  return event.key.toLowerCase()
}

function shortcutScope(root: HTMLElement): string {
  return root.dataset.shortcutScope || ""
}

function shortcutBindings(root: HTMLElement): ShortcutBinding[] {
  const encoded = root.dataset.shortcuts
  if (!encoded) return []

  try {
    const decoded = JSON.parse(encoded)
    return Array.isArray(decoded) ? decoded : []
  } catch {
    return []
  }
}

function matchingBinding(root: HTMLElement, key: string): ShortcutBinding | null {
  const scope = shortcutScope(root)

  return (
    shortcutBindings(root).find(
      (binding) => binding.keys.includes(key) && binding.scopes.includes(scope)
    ) || null
  )
}

function shouldIgnore(event: KeyboardEvent, binding: ShortcutBinding): boolean {
  return isInteractiveTarget(event.target) && !binding.captureInteractive
}

const Shortcuts: Partial<ShortcutsHook> = {
  mounted() {
    this.handleShortcutKeydown = (event) => {
      const key = normalizedKey(event)
      if (!key) return

      const binding = matchingBinding(this.el as HTMLElement, key)
      if (!binding || shouldIgnore(event, binding)) return

      if (binding.preventDefault) event.preventDefault()
      this.pushEvent("tilde:shortcut", { key })
    }

    window.addEventListener("keydown", this.handleShortcutKeydown)
  },

  destroyed() {
    if (this.handleShortcutKeydown)
      window.removeEventListener("keydown", this.handleShortcutKeydown)
  }
}

export default Shortcuts
