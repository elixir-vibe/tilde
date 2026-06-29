defmodule Tilde.Runtime.Metadata do
  @moduledoc """
  Sanitizes runtime-originated metadata before it crosses into durable Tilde events.

  Runtime metadata may contain BEAM-only values such as pids, references,
  functions, or rich structs from Jidoka/ReqLLM internals. Durable Tilde metadata
  keeps only simple map/list/scalar shapes. Unsafe map keys are dropped, unsafe
  values are removed, and structs are rendered with `inspect/1` rather than
  persisted as raw structs.
  """

  @doc "Returns runtime metadata with unsafe keys and values removed or normalized."
  @spec sanitize(map()) :: map()
  def sanitize(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      with sanitized_key when not is_nil(sanitized_key) <- sanitize_key(key),
           sanitized_value when not is_nil(sanitized_value) <- sanitize_value(value) do
        Map.put(acc, sanitized_key, sanitized_value)
      else
        _unsafe -> acc
      end
    end)
  end

  defp sanitize_key(key) when is_atom(key) or is_binary(key) or is_number(key), do: key
  defp sanitize_key(%_struct{} = key), do: inspect(key)
  defp sanitize_key(_key), do: nil

  defp sanitize_value(value)
       when is_pid(value) or is_reference(value) or is_function(value),
       do: nil

  defp sanitize_value(value)
       when is_binary(value) or is_number(value) or is_boolean(value),
       do: value

  defp sanitize_value(value) when is_atom(value), do: value

  defp sanitize_value(value) when is_list(value) do
    value
    |> Enum.map(&sanitize_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp sanitize_value(%_struct{} = value), do: inspect(value)

  defp sanitize_value(value) when is_map(value), do: sanitize(value)

  defp sanitize_value(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> sanitize_value()
  end

  defp sanitize_value(value), do: inspect(value)
end
