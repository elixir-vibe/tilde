defmodule Tilde.Storage.EventCodec do
  @moduledoc "Lossless event payload codec for durable storage rows."

  alias Tilde.Core.Event

  @codec "erlang-term-v1"

  @spec dump(Event.t()) :: map()
  def dump(%Event{} = event) do
    %{
      "codec" => @codec,
      "data" => event |> :erlang.term_to_binary() |> Base.encode64()
    }
  end

  @spec load(map()) :: {:ok, Event.t()} | {:error, term()}
  def load(%{"codec" => @codec, "data" => data}) when is_binary(data) do
    with {:ok, binary} <- Base.decode64(data),
         %Event{} = event <- :erlang.binary_to_term(binary, [:safe]) do
      {:ok, event}
    else
      :error -> {:error, :invalid_base64}
      other -> {:error, {:invalid_event_payload, other}}
    end
  rescue
    error in [ArgumentError] -> {:error, error}
  end

  def load(_payload), do: {:error, :unsupported_event_payload}

  @spec load!(map()) :: Event.t()
  def load!(payload) do
    case load(payload) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "invalid stored Tilde event: #{inspect(reason)}"
    end
  end
end
