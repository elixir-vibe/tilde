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
    .tilde-message-body { white-space: pre-wrap; }

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
    .tilde-tool-output { margin: 0.75rem 0 0; white-space: pre-wrap; overflow-x: auto; }
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

    .tilde-choice-options { display: grid; gap: 0.35rem; margin-top: 0.75rem; }
    .tilde-choice-option { text-align: left; text-decoration: none; color: var(--tilde-fg); }
    .tilde-choice-option.is-selected .tilde-choice-marker { color: var(--tilde-link); }
    .tilde-choice-description { color: var(--tilde-muted); margin-left: 0.75rem; }

    .tilde-input {
      border-top: 1px solid var(--tilde-line);
      border-bottom: 1px solid var(--tilde-line);
      display: grid;
      grid-template-columns: auto 1fr auto auto;
      gap: 0.75rem;
      align-items: start;
      padding: 0.75rem 0;
      margin: 1.5rem 0 0.75rem;
    }

    .tilde-input textarea {
      font: inherit;
      color: inherit;
      background: transparent;
      border: 0;
      resize: vertical;
      min-height: 1.55em;
      outline: none;
    }

    .tilde-footer { color: var(--tilde-muted); font-size: 0.9rem; }

    .tilde-demo-hooks {
      max-width: 920px;
      margin: 1rem auto;
      padding: 0 24px 24px;
      color: var(--tilde-fg);
      font: 14px/1.45 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }

    .tilde-demo-hooks summary { color: var(--tilde-link); cursor: pointer; }
    .tilde-demo-hooks pre { border: 1px solid var(--tilde-line); overflow-x: auto; padding: 0.75rem; }
    """
  end
end
