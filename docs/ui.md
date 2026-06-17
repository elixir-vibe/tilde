# Tilde UI system

Tilde's Live UI is a small DOM system backed by Volt-managed assets. Elixir owns
semantic state and markup. TypeScript owns browser behavior. CSS owns visual
presentation.

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
  reset.css
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

Add new component CSS under `components/` and import it from `app.css` in the
component layer.

## Naming rules

Only the root shell is namespaced:

```html
<main class="tilde">
```

Inside `.tilde`, use short component names:

```html
<section class="transcript">
<article class="block message">
<article class="block tool is-success">
<section class="dock">
<form class="input">
<footer class="footer">
```

CSS is always scoped through the root:

```css
.tilde .message {}
.tilde .tool.is-success {}
.tilde .markdown hr {}
```

Use `.is-*` classes for UI state. Use `data-*` attributes for semantics,
LiveView values, JS hooks, and tests.

## Component hierarchy

```text
.tilde
  .transcript
    .block.message[data-role]
      .label
      .message-body
        .markdown | .plain-text | runs
    .block.tool[data-block-id]
      .tool-header
      .tool-cell-lines
      .tool-footer
    .block.choice[data-block-id]
    .suggest
  .widgets.widgets-above
  .dock
    .input
    .widgets.widgets-below
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
