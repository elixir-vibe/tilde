defmodule Tilde.Live.Styles do
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
      }
    }

    .tilde-console {
      background: var(--tilde-bg);
      color: var(--tilde-fg);
      font: 16px/1.55 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      max-width: 920px;
      margin: 0 auto;
      padding: 24px;
    }

    .tilde-block { margin: 0 0 1.25rem; }
    .tilde-label, .tilde-muted, .tilde-tool-status, .tilde-key { color: var(--tilde-muted); }
    .tilde-label { margin-bottom: 0.25rem; }
    .tilde-message-body { white-space: normal; }
    .tilde-markdown { white-space: normal; }
    .tilde-plain-text { white-space: pre-wrap; }
    .tilde-markdown p, .tilde-markdown ul, .tilde-markdown ol, .tilde-markdown pre { margin: 0 0 0.75rem; }
    .tilde-markdown > :last-child { margin-bottom: 0; }
    .tilde-markdown a { color: var(--tilde-link); text-underline-offset: 2px; }
    .tilde-markdown pre { border: 1px solid var(--tilde-line); padding: 0.75rem; overflow-x: auto; }
    .tilde-markdown code { border: 1px solid var(--tilde-line); padding: 0 0.2em; }
    .tilde-markdown pre code { border: 0; padding: 0; }
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

    .tilde-tool-name { font-weight: 700; }
    .tilde-tool-args { color: var(--tilde-link); overflow-wrap: anywhere; }
    .tilde-tool-status { font-size: 0.9rem; }
    .tilde-tool-success .tilde-tool-status, .tilde-tool-done .tilde-tool-status { color: var(--tilde-success); }
    .tilde-tool-error .tilde-tool-status { color: var(--tilde-error); }
    .tilde-tool-running .tilde-tool-status, .tilde-tool-streaming .tilde-tool-status { color: var(--tilde-warning); }
    .tilde-tool-queued, .tilde-tool-cancelled { opacity: 0.82; }
    .tilde-tool-metadata { display: flex; flex-wrap: wrap; gap: 0.75rem; margin: 0.5rem 0 0; }
    .tilde-tool-metadata div { display: flex; gap: 0.25rem; }
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

    .tilde-suggest-title { color: var(--tilde-muted); margin-bottom: 0.35rem; }
    .tilde-suggest-items { display: grid; gap: 0.15rem; }
    .tilde-suggest-row {
      display: grid;
      grid-template-columns: 14ch 1fr;
      gap: 1rem;
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
      position: sticky;
      bottom: 0;
      z-index: 10;
      background: var(--tilde-bg);
      border-top: 1px solid var(--tilde-line);
      padding: 0.75rem 0 0;
      margin-top: 1.5rem;
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
    """
  end
end
