defmodule Tilde.Transport.Live.Styles do
  @moduledoc """
  Minimal elixir.toys-inspired CSS for Tilde Live components.
  """

  @doc "Returns the default CSS as a string."
  @spec css() :: String.t()
  def css do
    """
    :root {
      color-scheme: light dark;
      --tilde-bg: #faf7f0;
      --tilde-fg: #171411;
      --tilde-muted: #6f6860;
      --tilde-line: #ded6cb;
      --tilde-link: #5b2bbf;
      --tilde-success: #2f7d32;
      --tilde-error: #b3261e;
      --tilde-warning: #8a5a00;
      --tilde-tool-bg: rgba(222, 214, 203, 0.35);
      --tilde-tool-pending-bg: rgba(138, 90, 0, 0.10);
      --tilde-tool-success-bg: rgba(47, 125, 50, 0.10);
      --tilde-tool-error-bg: rgba(179, 38, 30, 0.10);
      --tilde-cell: 1ch;
      --tilde-scrollbar-thumb: #b9aea1;
      --tilde-scrollbar-thumb-hover: #8f8378;
    }

    html {
      height: 100%;
      background: var(--tilde-bg);
      overflow: hidden;
    }

    body {
      height: 100%;
      margin: 0;
      background: var(--tilde-bg);
      overflow: hidden;
      overscroll-behavior: none;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --tilde-bg: #11100f;
        --tilde-fg: #eee7dd;
        --tilde-muted: #aaa096;
        --tilde-line: #302c28;
        --tilde-link: #c7a8ff;
        --tilde-success: #8bc48a;
        --tilde-error: #ffb4ab;
        --tilde-warning: #e0b35a;
        --tilde-tool-bg: rgba(48, 44, 40, 0.45);
        --tilde-tool-pending-bg: rgba(224, 179, 90, 0.13);
        --tilde-tool-success-bg: rgba(139, 196, 138, 0.13);
        --tilde-tool-error-bg: rgba(255, 180, 171, 0.13);
        --tilde-scrollbar-thumb: #625a52;
        --tilde-scrollbar-thumb-hover: #8d8278;
      }
    }

    .tilde-console {
      background: var(--tilde-bg);
      color: var(--tilde-fg);
      font: 16px/1.55 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      max-width: 920px;
      height: 100dvh;
      box-sizing: border-box;
      margin: 0 auto;
      padding: 24px;
      display: flex;
      flex-direction: column;
    }

    .tilde-transcript {
      flex: 1 1 auto;
      min-height: 0;
      overflow-y: auto;
      overscroll-behavior: contain;
      scrollbar-gutter: auto;
    }

    @supports (scrollbar-width: thin) {
      .tilde-transcript {
        scrollbar-width: thin;
        scrollbar-color: var(--tilde-scrollbar-thumb) transparent;
      }
    }

    @supports selector(::-webkit-scrollbar) {
      .tilde-transcript {
        scrollbar-width: auto;
        scrollbar-color: auto;
      }

      .tilde-transcript::-webkit-scrollbar {
        width: 14px;
        height: 14px;
        background: transparent;
      }

      .tilde-transcript::-webkit-scrollbar-button,
      .tilde-transcript::-webkit-scrollbar-corner,
      .tilde-transcript::-webkit-resizer {
        display: none;
        background: transparent;
      }

      .tilde-transcript::-webkit-scrollbar-track,
      .tilde-transcript::-webkit-scrollbar-track-piece {
        background: transparent;
        border: 0;
        box-shadow: none;
      }

      .tilde-transcript::-webkit-scrollbar-thumb {
        min-height: 44px;
        background-color: color-mix(in srgb, var(--tilde-scrollbar-thumb) 72%, transparent);
        background-clip: content-box;
        border: 4px solid transparent;
        border-radius: 999px;
        box-shadow: none;
      }

      .tilde-transcript::-webkit-scrollbar-thumb:hover {
        background-color: color-mix(in srgb, var(--tilde-scrollbar-thumb-hover) 88%, transparent);
        border-width: 3px;
      }

      .tilde-transcript::-webkit-scrollbar-thumb:active {
        background-color: var(--tilde-scrollbar-thumb-hover);
        border-width: 3px;
      }
    }

    .tilde-block { margin: 0 0 1.25rem; }
    .tilde-label, .tilde-muted, .tilde-key, .tilde-shortcut { color: var(--tilde-muted); }
    .tilde-label { margin-bottom: 0.25rem; }
    .tilde-message-body { white-space: normal; }
    .tilde-markdown { white-space: normal; overflow-x: auto; }
    .tilde-plain-text { white-space: pre-wrap; }
    .tilde-markdown p, .tilde-markdown ul, .tilde-markdown ol, .tilde-markdown pre { margin: 0 0 0.75rem; }
    .tilde-markdown > :last-child { margin-bottom: 0; }
    .tilde-markdown a { color: var(--tilde-link); text-underline-offset: 2px; }
    .tilde-markdown pre { border: 1px solid var(--tilde-line); padding: 0.75rem; overflow-x: auto; }
    .tilde-markdown table {
      border-collapse: collapse;
      border-spacing: 0;
      font: inherit;
      width: auto;
      max-width: 100%;
      margin: 0 0 1lh;
    }
    .tilde-markdown th,
    .tilde-markdown td {
      border: 1px solid var(--tilde-line);
      padding: 0 var(--tilde-cell);
      text-align: left;
      vertical-align: top;
      white-space: nowrap;
    }
    .tilde-markdown th {
      color: var(--tilde-muted);
      font-weight: 400;
    }
    .tilde-markdown th[align="center"], .tilde-markdown td[align="center"] { text-align: center; }
    .tilde-markdown th[align="right"], .tilde-markdown td[align="right"] { text-align: right; }
    .tilde-markdown code { border: 1px solid var(--tilde-line); padding: 0 0.2em; }
    .tilde-markdown pre code { border: 0; padding: 0; }
    .tilde-view-text-title { font-weight: 700; }
    .tilde-view-text-accent { color: var(--tilde-link); }
    .tilde-view-text-muted, .tilde-view-text-shortcut { color: var(--tilde-muted); }
    .tilde-view-text-primary { color: var(--tilde-fg); }
    .tilde-view-text-success { color: var(--tilde-success); }
    .tilde-view-text-error { color: var(--tilde-error); }
    .tilde-view-text-warning { color: var(--tilde-warning); }

    .tilde-run-muted { color: var(--tilde-muted); }
    .tilde-run-accent { color: var(--tilde-link); }
    .tilde-run-error { color: var(--tilde-error); }
    .tilde-run-success { color: var(--tilde-success); }
    .tilde-run-code code, .tilde-message-body code {
      border: 1px solid var(--tilde-line);
      padding: 0 0.2em;
    }

    .tilde-tool, .tilde-choice, .tilde-widget {
      border: 1px solid var(--tilde-line);
      background: var(--tilde-tool-bg);
      padding: 0.75rem;
    }

    .tilde-tool-header, .tilde-footer {
      display: flex;
      gap: 0.75rem;
      justify-content: space-between;
      align-items: baseline;
    }

    .tilde-tool-queued, .tilde-tool-running, .tilde-tool-streaming { background: var(--tilde-tool-pending-bg); }
    .tilde-tool-success, .tilde-tool-done { background: var(--tilde-tool-success-bg); }
    .tilde-tool-error { background: var(--tilde-tool-error-bg); }
    .tilde-tool-cancelled { opacity: 0.82; }
    .tilde-tool-call { min-width: 0; overflow-wrap: anywhere; }
    .tilde-tool-name { font-weight: 700; }
    .tilde-tool-segment { margin-left: var(--tilde-cell); }
    .tilde-tool-segment-accent { color: var(--tilde-link); }
    .tilde-tool-segment-muted, .tilde-tool-segment-dim, .tilde-tool-tags, .tilde-tool-suffix { color: var(--tilde-muted); }
    .tilde-tool-segment-success { color: var(--tilde-success); }
    .tilde-tool-tags, .tilde-tool-suffix { margin-left: var(--tilde-cell); }
    .tilde-tool-metadata { display: flex; flex-wrap: wrap; gap: 0.75rem; margin: 0.5rem 0 0; }
    .tilde-tool-cell-lines { margin-top: 0.75rem; display: grid; gap: 0.15rem; white-space: pre-wrap; }
    .tilde-tool-cell-line { overflow-wrap: anywhere; }
    .tilde-tool-waiting { color: var(--tilde-muted); margin-top: 0.75rem; }
    .tilde-tool-metadata div { display: flex; gap: var(--tilde-cell); }
    .tilde-tool-metadata dt { color: var(--tilde-muted); }
    .tilde-tool-metadata dd { margin: 0; }
    .tilde-tool-streams { display: grid; gap: 0.5rem; margin-top: 0.75rem; }
    .tilde-tool-stream-label { color: var(--tilde-muted); font-size: 0.9rem; }
    .tilde-tool-stream pre { margin: 0; white-space: pre-wrap; overflow-x: auto; }
    .tilde-tool-stream-stderr { color: var(--tilde-error); }
    .tilde-tool-stream-log { color: var(--tilde-muted); }
    .tilde-tool-stream-result { color: var(--tilde-success); }
    .tilde-tool-footer, .tilde-choice-actions { margin-top: 0.75rem; display: flex; gap: 0.75rem; }

    .tilde-link-button, .tilde-action, .tilde-choice-option {
      font: inherit;
      color: var(--tilde-link);
      background: transparent;
      border: 0;
      padding: 0;
      cursor: pointer;
      text-decoration: underline;
      text-underline-offset: 2px;
    }

    .tilde-shortcut { display: inline-flex; gap: 0.35em; align-items: baseline; margin-left: 0.35em; }
    .tilde-shortcut:first-child { margin-left: 0; }
    .tilde-shortcut-key {
      font: inherit;
      color: var(--tilde-muted);
      border: 1px solid var(--tilde-line);
      border-radius: 0;
      padding: 0 0.25em;
      background: transparent;
    }
    .tilde-shortcut-label { color: var(--tilde-link); }

    .tilde-suggest-title { color: var(--tilde-muted); margin-bottom: 0.35rem; }
    .tilde-suggest-items { display: grid; gap: 0.15rem; }
    .tilde-suggest-row {
      display: grid;
      grid-template-columns: 14ch 1fr;
      gap: 2ch;
      width: 100%;
      font: inherit;
      color: inherit;
      background: transparent;
      border: 0;
      padding: 0.1rem 0;
      text-align: left;
      cursor: pointer;
    }
    .tilde-suggest-row:hover { color: var(--tilde-link); }
    .tilde-suggest-row code { color: var(--tilde-link); border: 0; padding: 0; }
    .tilde-suggest-row span { color: var(--tilde-muted); }

    .tilde-choice-options { display: grid; gap: 0.35rem; margin-top: 0.75rem; }
    .tilde-choice-option { text-align: left; text-decoration: none; color: var(--tilde-fg); }
    .tilde-choice-option.is-selected .tilde-choice-marker { color: var(--tilde-link); }
    .tilde-choice-description { color: var(--tilde-muted); margin-left: 0.75rem; }

    .tilde-dock {
      flex: 0 0 auto;
      z-index: 10;
      background: var(--tilde-bg);
      border-top: 1px solid var(--tilde-line);
      padding: 0 0 max(0.25rem, env(safe-area-inset-bottom));
      margin-top: 0;
    }

    .tilde-agent-pending {
      color: var(--tilde-muted);
      font-size: 0.9rem;
      padding: 0.5rem 0 0.25rem;
    }

    .tilde-input {
      display: grid;
      grid-template-columns: 1fr auto auto;
      gap: 0.75rem;
      align-items: start;
      padding: 0 0 0.75rem;
    }

    .tilde-input textarea {
      font: inherit;
      color: inherit;
      background: transparent;
      border: 0;
      resize: none;
      overflow: hidden;
      min-height: 1.55em;
      max-height: 12rem;
      outline: none;
    }

    .tilde-footer { color: var(--tilde-muted); font-size: 0.9rem; }

    @media (max-width: 640px), (pointer: coarse) {
      .tilde-shortcut-key { display: none; }
      .tilde-shortcut { margin-left: 0; }
    }
    """
  end
end
