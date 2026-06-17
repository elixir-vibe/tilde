# UI architecture roadmap

## End-state architecture

```text
Core state
  Session / Index / Transcript / Input

Semantic UI composition
  Core.Widget as the shared composition unit
  Core.Suggest / Choice / Action / Display as widget content contracts
  HEEx templates compose Widgets, not cells

Renderer adapters
  Live renders Widgets -> DOM
  TUI renders Widgets -> Cells/ANSI
  SSH uses TUI renderer

Low-level projection
  View.Cell / View.Line / View.Text only for TUI-ish projection
```

## Roadmap

1. Clean partial index/rendering work.
   - Remove renderer-owned index layout.
   - Remove inline index screen composition from demo LiveView.
   - Keep `Tilde.Core.Index` only as semantic state/behavior.
   - Keep `Tilde.Session.Summary` only as pure semantic session summary.

2. Strengthen `Tilde.Core.Widget`.
   - Treat it as the shared semantic composition unit.
   - Define widget kinds/contracts such as `:screen`, `:section`, `:text`, `:suggest`, `:input`, `:shortcut_bar`, `:footer`.
   - Avoid a parallel semantic-node hierarchy.

3. Introduce index state correctly.
   - `Tilde.Core.Index` owns input, selection, command suggestions, and session suggestions.
   - It contains no DOM/ANSI/cell concerns.
   - Behaviors: command suggestions, `/new ` completion, `/attach ` real-session suggestions, up/down, enter, escape, and `n` -> `/new `.

4. Add `Tilde.Index.View`.
   - Semantic composition only.
   - `Tilde.Index.View.widgets(index)` returns a `Core.Widget` tree/list.
   - It is the single source of truth for index appearance.

5. Move session previews to shared semantic helper.
   - `Tilde.Session.Summary` owns first/last extraction and bounded plain text excerpts.
   - Used by index and `/attach` suggestions.
   - No synthetic sessions.

6. Upgrade semantic HEEx templates to output widgets.
   - Add `Tilde.Template.to_widgets!`.
   - Keep `to_cells!` as projection/legacy path.
   - New semantic composition should target widgets first, cells later.

7. Refactor tool template path.
   - Move from direct cell construction toward tool semantic widget composition.
   - Preserve current Live/TUI appearance.

8. Create Live widget renderer.
   - `Tilde.Transport.Live.WidgetRenderer` renders `Core.Widget` to DOM.
   - Reuse existing Live components for input, shortcut, footer, suggest, etc.
   - Demo LiveView dispatches events and chooses mode only.

9. Create TUI widget renderer.
   - `Tilde.Renderer.TUI.WidgetRenderer` projects widgets to `View.Cell/Line/Text` and ANSI.
   - Cells remain low-level TUI projection only.
   - No dedicated manual TUI index renderer.

10. Route/navigation model.
    - Web root is index.
    - Session path opens a real named session.
    - No special demo session.
    - SSH/TUI starts on index; `/detach` returns to index.

11. Command argument suggestions.
    - Generic command layer delegates arg suggestions to command modules.
    - `Attach` owns session suggestions.
    - `New` owns session-name hints.

12. Browser and TUI tests.
    - Core index behavior tests.
    - Browser index tests using PlaywrightEx helpers.
    - SSH/TUI index tests.

13. Documentation.
    - Update `docs/session-model.md` and `docs/ui.md` with the final layering.

14. Full cleanup and validation.
    - Remove stale renderer-specific state from core.
    - Remove fake sessions and duplicated preview logic.
    - Run `mix format`, Volt checks/build, and `mix ci`.
