defmodule Tilde.Session.Suggestions do
  @moduledoc "Command suggestion behavior for semantic sessions."

  alias Tilde.Command
  alias Tilde.Core.{Input, Session, Suggest, Widget}

  @doc "Returns the active command suggestion widget content."
  @spec command_suggestions(Session.t()) :: Suggest.t() | nil
  def command_suggestions(%Session{} = session) do
    session
    |> Session.widgets(:above_input)
    |> Enum.find_value(fn
      %Widget{id: "command-suggestions", content: %Suggest{} = suggest} -> suggest
      _widget -> nil
    end)
  end

  @doc "Refreshes command suggestions for the current input value."
  @spec refresh(Session.t()) :: Session.t()
  def refresh(%Session{} = session) do
    previous_id = command_suggestions(session) && command_suggestions(session).selected_id

    case Command.suggestions(session.input.value) do
      nil ->
        cancel(session)

      suggest ->
        Session.put_widget(
          session,
          Widget.new(
            "command-suggestions",
            :above_input,
            Suggest.select_id(suggest, previous_id)
          )
        )
    end
  end

  @doc "Moves the active command suggestion selection forward."
  @spec select_next(Session.t()) :: Session.t()
  def select_next(%Session{} = session), do: update(session, &Suggest.next/1)

  @doc "Moves the active command suggestion selection backward."
  @spec select_previous(Session.t()) :: Session.t()
  def select_previous(%Session{} = session), do: update(session, &Suggest.previous/1)

  @doc "Clears active command suggestions."
  @spec cancel(Session.t()) :: Session.t()
  def cancel(%Session{} = session), do: Session.delete_widget(session, "command-suggestions")

  @doc "Accepts the selected command suggestion into the input draft."
  @spec accept(Session.t()) :: {:ok, Session.t()} | :error
  def accept(%Session{} = session) do
    case selected_completion(session) do
      nil -> :error
      completion -> {:ok, change_input(session, Input.put_value(session.input, completion))}
    end
  end

  @doc "Submits the selected command suggestion, or completes it when it needs arguments."
  @spec submit(Session.t()) :: {:ok, Session.t()} | :error
  def submit(%Session{} = session) do
    case selected_completion(session) do
      nil ->
        :error

      completion ->
        if String.ends_with?(completion, " ") do
          {:ok, change_input(session, Input.put_value(session.input, completion))}
        else
          {:ok, Session.append_event(session, Tilde.input_submitted(completion))}
        end
    end
  end

  defp selected_completion(%Session{} = session) do
    case command_suggestions(session) do
      %Suggest{} = suggest -> Suggest.accept(suggest)
      nil -> nil
    end
  end

  defp update(%Session{} = session, fun) when is_function(fun, 1) do
    case command_suggestions(session) do
      %Suggest{} = suggest ->
        Session.put_widget(
          session,
          Widget.new("command-suggestions", :above_input, fun.(suggest))
        )

      nil ->
        session
    end
  end

  defp change_input(%Session{} = session, %Input{} = input) do
    session
    |> Session.append_event(Tilde.input_changed(input.value, metadata: %{cursor: input.cursor}))
    |> refresh()
  end
end
