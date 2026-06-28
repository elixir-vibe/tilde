import type { ViewHook } from "phoenix_live_view"

const PaletteInput: Partial<ViewHook> = {
  mounted() {
    if (this.el instanceof HTMLInputElement) {
      this.el.focus()
      this.el.select()
    }
  },

  updated() {
    if (this.el instanceof HTMLInputElement && document.activeElement !== this.el) {
      this.el.focus()
    }
  }
}

export default PaletteInput
