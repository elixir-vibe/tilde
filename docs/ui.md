# Tilde UI system

Tilde's UI is shared across LiveView, TUI, and SSH. Elixir owns semantic state
and widget composition. TypeScript owns browser behavior. CSS owns visual
presentation.

## Architecture layers

```text
Core state
  Session / Index / Transcript / Input

Semantic UI composition
  Tilde.Core.Widget as the shared composition unit
  Tilde.Core.Suggest / Choice / Action / Display as widget content contracts
  Tilde.Template HEEx composes widgets first; cells are only a projection

Renderer adapters
  Tilde.Transport.Live.WidgetRenderer projects widgets to DOM
  Tilde.Renderer.TUI.WidgetRenderer projects widgets to terminal text/cells
  SSH uses the TUI projection

Low-level projection
  Tilde.View.Cell / Line / Text are TUI-ish projection primitives, not the
  semantic source of truth
```

`Tilde.Index.View` is the shared index appearance source. The demo LiveView and
SSH/TUI should consume that widget composition rather than owning index layout.

## Asset entrypoints

```text
assets/js/app.ts          # LiveSocket entrypoint
assets/js/hooks/*.ts      # LiveView hooks
assets/css/app.css        # cascade-layer entrypoint
```

The demo layout links these through `Volt.static_path/2`:

```elixir
Volt.static_path(Tilde.Demo.Endpoint, "/assets/css/app.css")
Volt.static_path(Tilde.Demo.Endpoint, "/assets/js/app.js")
```

Volt provides TypeScript compilation, HMR, production builds, and JS/TS
format/lint checks.

## CSS source tree

```text
assets/css/tilde/
  tokens.css
  layout.css
  components/
    message.css
    markdown.css
    text.css
    run.css
    tool.css
    shortcut.css
    suggest.css
    choice.css
    widget.css
    input.css
    footer.css
```

`assets/css/app.css` imports files into cascade layers in this order:

```css
@layer tokens, reset, layout, components, utilities;
```

The reset layer imports `modern-normalize` directly from npm; do not add a local
wrapper file for package CSS. Add new component CSS under `components/` and
import it from `app.css` in the component layer.

## Naming rules

Only the root shell is namespaced:

```html
<main class="tilde">
```

Inside `.tilde`, use short component names:

```html
<section class="transcript">
<article class="block message">
<article class="block tool success">
<section class="dock">
<form class="input">
<footer class="footer">
```

CSS is always scoped through the root with nested rules:

```css
.tilde {
  .message {}

  .tool {
    &.success {}
  }

  .markdown {
    hr {}
  }
}
```

Use short state classes such as `.success`, `.selected`, and `.pending` inside
component scope. Use `data-*` attributes for semantics, LiveView values, JS
hooks, and tests.

## Component hierarchy

```text
.tilde
  .transcript
    .block.message[data-role]
      .label
      .body
        .markdown | .plain | runs
    .block.tool[data-block-id]
      .header
      .lines
      .footer
    .block.choice[data-block-id]
    .suggest
  .widgets[data-placement="above_input"]
  .dock
    .input
    .widgets[data-placement="below_input"]
    .footer
```

## Tokens

Tokens live on `.tilde`, not `:root`, so host apps can embed multiple shells or
wrap Tilde without leaking variables globally.

Token categories:

- `--color-*` for foreground, muted text, borders, links, and semantic colors
- `--surface-*` for panels/tool states
- `--space-*` for rhythm and terminal-cell spacing
- `--font-*`, `--text-*`, `--leading-*` for typography
- `--content-max` for console width

Components should consume tokens and avoid literal colors/spacing unless a value
is intrinsic to the component shape.
