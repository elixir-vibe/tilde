import Console from "./console"
import Devtools from "./devtools"
import PaletteInput from "./palette-input"
import Shortcuts from "./shortcuts"
import WorkspaceFile from "./workspace-file"

const hooks = {
  TildeConsole: Console,
  TildeDevtools: Devtools,
  TildePaletteInput: PaletteInput,
  TildeShortcuts: Shortcuts,
  TildeWorkspaceFile: WorkspaceFile
}

export default hooks
