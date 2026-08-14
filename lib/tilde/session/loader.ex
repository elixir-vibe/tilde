defmodule Tilde.Session.Loader do
  @moduledoc "Loads a persisted session or creates a fresh semantic session."

  alias Tilde.Core.Session
  alias Tilde.Storage

  @spec load_or_new(String.t(), keyword()) :: Session.t()
  def load_or_new(session_id, opts \\ []) when is_binary(session_id) do
    new_fun = Keyword.get(opts, :new, fn -> Tilde.session(id: session_id) end)

    case Storage.adapter() do
      nil ->
        new_fun.()

      _adapter ->
        case Storage.load_session(session_id) do
          {:ok, %Session{} = session} -> use_loaded_or_new(session, new_fun)
          {:error, _reason} -> new_fun.()
        end
    end
  end

  defp use_loaded_or_new(%Session{} = session, new_fun) do
    if Session.empty?(session), do: new_fun.(), else: session
  end
end
