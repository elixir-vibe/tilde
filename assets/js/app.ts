import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import TildeConsole from "./hooks/tilde-console"

const hooks = { TildeConsole }
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

if (import.meta.hot) {
  import.meta.hot.accept()
}
