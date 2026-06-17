defmodule Tilde.Core.Interaction do
  @moduledoc """
  Transport-neutral user interaction for console surfaces.

  Durable transcript/domain events live in `Tilde.Core.Event`. Interactions are
  ephemeral user intents translated from LiveView events, terminal keys, or other
  transports before they are applied to core state.
  """

  defstruct type: nil, payload: %{}

  @type type ::
          :input_changed
          | :complete_input
          | :suggest_next
          | :suggest_previous
          | :suggest_cancel
          | :suggest_accept
          | :suggest_submit
          | :submit
          | :interrupt
          | :new_shortcut
          | :quit
          | :toggle_expand
          | :select_choice
          | :choice_action

  @type t :: %__MODULE__{type: type(), payload: map()}

  @spec new(type(), map()) :: t()
  def new(type, payload \\ %{}) when is_atom(type) and is_map(payload) do
    %__MODULE__{type: type, payload: payload}
  end

  @spec input_changed(String.t()) :: t()
  def input_changed(input), do: new(:input_changed, %{input: input})

  @spec complete_input(String.t()) :: t()
  def complete_input(insert), do: new(:complete_input, %{insert: insert})

  @spec submit(String.t()) :: t()
  def submit(input), do: new(:submit, %{input: input})
end

defmodule Tilde.Core.Interaction.Outcome do
  @moduledoc "Transport-neutral outcome requested by applying an interaction."

  defstruct type: nil, payload: %{}

  @type type :: :complete_input | :open_session | :open_index | :show_session_info
  @type t :: %__MODULE__{type: type(), payload: map()}

  @spec complete_input(String.t()) :: t()
  def complete_input(input), do: %__MODULE__{type: :complete_input, payload: %{input: input}}

  @spec open_session(String.t(), keyword()) :: t()
  def open_session(id, opts \\ []) do
    payload = %{id: id} |> maybe_put(:submit, Keyword.get(opts, :submit))
    %__MODULE__{type: :open_session, payload: payload}
  end

  @spec open_index() :: t()
  def open_index, do: %__MODULE__{type: :open_index, payload: %{}}

  @spec show_session_info() :: t()
  def show_session_info, do: %__MODULE__{type: :show_session_info, payload: %{}}

  @spec from_command_effects([Tilde.Command.Effect.t()]) :: [t()]
  def from_command_effects(effects) do
    Enum.flat_map(effects, fn
      %Tilde.Command.Effect.NewSession{id: id} -> [open_session(id)]
      %Tilde.Command.Effect.AttachSession{id: id} -> [open_session(id)]
      %Tilde.Command.Effect.DetachSession{} -> [open_index()]
      %Tilde.Command.Effect.ShowSessionInfo{} -> [show_session_info()]
      _effect -> []
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
