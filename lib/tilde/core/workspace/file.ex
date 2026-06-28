defmodule Tilde.Core.Workspace.File do
  @moduledoc """
  Renderer-neutral file entry for the persistent workspace file pane.
  """

  defstruct path: "",
            name: "",
            kind: :file,
            language: nil,
            size: nil,
            git_status: :clean,
            session_state: :untouched,
            previewable?: true

  @type kind :: :file | :directory
  @type git_status :: :clean | :modified | :added | :deleted | :renamed | :untracked | :conflicted
  @type session_state :: :untouched | :read | :modified

  @type t :: %__MODULE__{
          path: String.t(),
          name: String.t(),
          kind: kind(),
          language: atom() | nil,
          size: non_neg_integer() | nil,
          git_status: git_status(),
          session_state: session_state(),
          previewable?: boolean()
        }

  @doc "Returns compact status marks for terminal-style file rows."
  @spec marks(t()) :: String.t()
  def marks(%__MODULE__{} = file) do
    [session_mark(file.session_state), git_mark(file.git_status)]
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> " "
      marks -> Enum.join(marks)
    end
  end

  defp session_mark(:modified), do: "M"
  defp session_mark(:read), do: "R"
  defp session_mark(_state), do: ""

  defp git_mark(:clean), do: ""
  defp git_mark(:modified), do: "~"
  defp git_mark(:added), do: "+"
  defp git_mark(:deleted), do: "×"
  defp git_mark(:renamed), do: "↪"
  defp git_mark(:untracked), do: "?"
  defp git_mark(:conflicted), do: "!"

  @doc "Builds a file entry."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    path = Keyword.get(opts, :path, "")

    %__MODULE__{
      path: path,
      name: Keyword.get(opts, :name, Path.basename(path)),
      kind: Keyword.get(opts, :kind, :file),
      language: Keyword.get(opts, :language),
      size: Keyword.get(opts, :size),
      git_status: Keyword.get(opts, :git_status, :clean),
      session_state: Keyword.get(opts, :session_state, :untouched),
      previewable?: Keyword.get(opts, :previewable?, true)
    }
  end
end
