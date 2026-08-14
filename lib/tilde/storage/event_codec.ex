defmodule Tilde.Storage.EventCodec do
  @moduledoc """
  Versioned, JSON-portable codec for durable session events.

  Event fields use an explicit schema. Values that JSON cannot represent
  directly—atoms, tuples, binary data, maps with non-string keys, and temporal
  values—use tagged maps.
  """

  alias Tilde.Core.Event

  @codec "tilde-event-json"
  @version 1
  @tag "$tilde"

  @event_fields [
    :id,
    :sequence,
    :type,
    :at,
    :block_id,
    :tool_call_id,
    :role,
    :text,
    :name,
    :args,
    :stream,
    :chunk,
    :status,
    :result,
    :display,
    :metadata
  ]

  @event_types [
    :user_message,
    :assistant_turn_started,
    :assistant_delta,
    :assistant_done,
    :assistant_turn_finished,
    :assistant_turn_error,
    :assistant_turn_cancelled,
    :tool_started,
    :tool_stream,
    :tool_done,
    :block_display_changed,
    :input_changed,
    :input_submitted,
    :status_changed,
    :context_compacted
  ]

  @doc "Encodes one event into a versioned JSON-compatible map."
  @spec dump(Event.t()) :: map()
  def dump(%Event{} = event) do
    encoded =
      Map.new(@event_fields, fn field ->
        {Atom.to_string(field), event |> Map.fetch!(field) |> encode_value!()}
      end)

    %{"codec" => @codec, "version" => @version, "event" => encoded}
  end

  @doc "Decodes a portable event payload."
  @spec load(map()) :: {:ok, Event.t()} | {:error, term()}
  def load(%{"codec" => @codec, "version" => @version, "event" => encoded})
      when is_map(encoded) do
    decode_event(encoded)
  end

  def load(%{"codec" => @codec, "version" => version}),
    do: {:error, {:unsupported_event_version, version}}

  def load(_payload), do: {:error, :unsupported_event_payload}

  @doc "Decodes a stored event or raises for malformed/unsupported payloads."
  @spec load!(map()) :: Event.t()
  def load!(payload) do
    case load(payload) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "invalid stored Tilde event: #{inspect(reason)}"
    end
  end

  defp decode_event(encoded) do
    with {:ok, attrs} <- decode_event_fields(encoded),
         %Event{} = event <- struct(Event, attrs),
         :ok <- validate_event(event) do
      {:ok, event}
    end
  end

  defp decode_event_fields(encoded) do
    Enum.reduce_while(@event_fields, {:ok, %{}}, fn field, {:ok, attrs} ->
      key = Atom.to_string(field)

      with {:ok, value} <- Map.fetch(encoded, key),
           {:ok, decoded} <- decode_value(value) do
        {:cont, {:ok, Map.put(attrs, field, decoded)}}
      else
        :error -> {:halt, {:error, {:missing_event_field, key}}}
        {:error, reason} -> {:halt, {:error, {:invalid_event_field, key, reason}}}
      end
    end)
  end

  defp validate_event(%Event{id: id, sequence: sequence, type: type}) do
    cond do
      not is_binary(id) ->
        {:error, :invalid_event_id}

      not (is_nil(sequence) or (is_integer(sequence) and sequence >= 0)) ->
        {:error, :invalid_event_sequence}

      type not in @event_types ->
        {:error, {:invalid_event_type, type}}

      true ->
        :ok
    end
  end

  defp encode_value!(value) do
    case encode_value(value) do
      {:ok, encoded} ->
        encoded

      {:error, reason} ->
        raise ArgumentError, "event contains non-portable value: #{inspect(reason)}"
    end
  end

  defp encode_value(nil), do: {:ok, nil}
  defp encode_value(value) when is_boolean(value) or is_integer(value), do: {:ok, value}
  defp encode_value(value) when is_float(value), do: {:ok, value}

  defp encode_value(value) when is_binary(value) do
    if String.valid?(value) do
      {:ok, value}
    else
      {:ok, %{@tag => "bytes", "base64" => Base.encode64(value)}}
    end
  end

  defp encode_value(value) when is_atom(value),
    do: {:ok, %{@tag => "atom", "value" => Atom.to_string(value)}}

  defp encode_value(%DateTime{} = value),
    do: {:ok, %{@tag => "datetime", "value" => DateTime.to_iso8601(value)}}

  defp encode_value(%NaiveDateTime{} = value),
    do: {:ok, %{@tag => "naive_datetime", "value" => NaiveDateTime.to_iso8601(value)}}

  defp encode_value(%Date{} = value),
    do: {:ok, %{@tag => "date", "value" => Date.to_iso8601(value)}}

  defp encode_value(%Time{} = value),
    do: {:ok, %{@tag => "time", "value" => Time.to_iso8601(value)}}

  defp encode_value(value) when is_tuple(value) do
    with {:ok, items} <- encode_many(Tuple.to_list(value)) do
      {:ok, %{@tag => "tuple", "items" => items}}
    end
  end

  defp encode_value(value) when is_list(value) do
    encode_many(value)
  end

  defp encode_value(%module{} = value) do
    with {:ok, fields} <- encode_value(Map.from_struct(value)) do
      {:ok,
       %{
         @tag => "struct",
         "module" => Atom.to_string(module),
         "fields" => fields
       }}
    end
  end

  defp encode_value(value) when is_map(value) do
    with {:ok, entries} <- encode_entries(Map.to_list(value)) do
      {:ok, %{@tag => "map", "entries" => entries}}
    end
  end

  defp encode_value(value), do: {:error, {:unsupported_term, inspect(value)}}

  defp encode_many(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, encoded} ->
      case encode_value(value) do
        {:ok, item} -> {:cont, {:ok, [item | encoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_encoded()
  rescue
    Protocol.UndefinedError -> {:error, :improper_list}
  end

  defp encode_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, encoded} ->
      with {:ok, encoded_key} <- encode_value(key),
           {:ok, encoded_value} <- encode_value(value) do
        {:cont, {:ok, [[encoded_key, encoded_value] | encoded]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_encoded()
  end

  defp reverse_encoded({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_encoded({:error, _reason} = error), do: error

  defp decode_value(nil), do: {:ok, nil}

  defp decode_value(value)
       when is_boolean(value) or is_integer(value) or is_float(value) or is_binary(value),
       do: {:ok, value}

  defp decode_value(%{@tag => "atom", "value" => value}) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, {:unknown_atom, value}}
  end

  defp decode_value(%{@tag => "bytes", "base64" => value}) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_value(%{@tag => "tuple", "items" => items}) when is_list(items) do
    with {:ok, decoded} <- decode_many(items), do: {:ok, List.to_tuple(decoded)}
  end

  defp decode_value(%{@tag => "map", "entries" => entries}) when is_list(entries) do
    decode_entries(entries)
  end

  defp decode_value(%{@tag => "struct", "module" => name, "fields" => encoded})
       when is_binary(name) do
    with {:ok, fields} <- decode_value(encoded),
         {:ok, module} <- existing_module(name) do
      build_struct(module, fields)
    end
  end

  defp decode_value(%{@tag => "datetime", "value" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_datetime, reason}}
    end
  end

  defp decode_value(%{@tag => "naive_datetime", "value" => value}) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_naive_datetime, reason}}
    end
  end

  defp decode_value(%{@tag => "date", "value" => value}) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, reason} -> {:error, {:invalid_date, reason}}
    end
  end

  defp decode_value(%{@tag => "time", "value" => value}) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, reason} -> {:error, {:invalid_time, reason}}
    end
  end

  defp decode_value(value) when is_list(value), do: decode_many(value)
  defp decode_value(%{@tag => type}), do: {:error, {:unsupported_value_tag, type}}
  defp decode_value(value) when is_map(value), do: {:error, {:untagged_map, value}}
  defp decode_value(value), do: {:error, {:unsupported_value, value}}

  defp decode_many(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, decoded} ->
      case decode_value(value) do
        {:ok, item} -> {:cont, {:ok, [item | decoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_encoded()
  end

  defp existing_module(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, {:unknown_struct_module, name}}
  end

  defp build_struct(module, fields) when is_map(fields) do
    {:ok, struct!(module, fields)}
  rescue
    error in [ArgumentError, KeyError] -> {:error, {:invalid_struct, module, error}}
  end

  defp build_struct(module, fields), do: {:error, {:invalid_struct_fields, module, fields}}

  defp decode_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn
      [encoded_key, encoded_value], {:ok, decoded} ->
        with {:ok, key} <- decode_value(encoded_key),
             {:ok, value} <- decode_value(encoded_value) do
          {:cont, {:ok, Map.put(decoded, key, value)}}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end

      entry, _decoded ->
        {:halt, {:error, {:invalid_map_entry, entry}}}
    end)
  end
end
