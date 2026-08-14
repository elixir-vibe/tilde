defmodule Tilde.Storage.EventCodecTest do
  use TildeTest.Case, async: true

  alias Tilde.Storage.EventCodec

  test "round-trips a sequenced event through a JSON-compatible versioned payload" do
    event =
      Tilde.context_compacted("## Context Compaction\n\nSummary",
        sequence: 7,
        at: ~U[2026-06-17 12:34:56.123456Z],
        metadata: %{
          1 => <<0, 255>>,
          first_kept_block_id: "msg_1",
          tokens_before: 1234,
          tuple: {:ok, :preserved}
        }
      )

    payload = EventCodec.dump(event)

    assert %{"codec" => "tilde-event-json", "version" => 1, "event" => encoded} = payload
    assert encoded["sequence"] == 7
    json_payload = payload |> Jason.encode!() |> Jason.decode!()
    assert EventCodec.load!(json_payload) == event
  end

  test "round-trips portable nested result values losslessly" do
    event =
      Tilde.tool_done(
        "call-1",
        :success,
        {:ok, %{answer: [1, 2, 3], uri: URI.parse("https://tilde.local/path")}},
        metadata: %{nested: {:tuple, :value}}
      )

    assert EventCodec.load!(EventCodec.dump(event)) == event
  end

  test "rejects malformed and unsupported stored payloads" do
    payload = EventCodec.dump(Tilde.input_submitted("hello", sequence: 0))
    encoded = payload["event"]

    assert {:error, {:missing_event_field, "id"}} =
             EventCodec.load(%{payload | "event" => Map.delete(encoded, "id")})

    malformed_metadata = %{"$tilde" => "map", "entries" => [["missing-value"]]}

    assert {:error, {:invalid_event_field, "metadata", {:invalid_map_entry, _entry}}} =
             EventCodec.load(%{
               payload
               | "event" => Map.put(encoded, "metadata", malformed_metadata)
             })

    assert {:error, :unsupported_event_payload} =
             EventCodec.load(%{"codec" => "unknown", "version" => 1})
  end

  test "rejects unsupported versions and runtime-only values" do
    assert {:error, {:unsupported_event_version, 2}} =
             EventCodec.load(%{"codec" => "tilde-event-json", "version" => 2})

    event = Tilde.tool_done("call-1", :success, self())

    assert_raise ArgumentError, ~r/non-portable value/, fn ->
      EventCodec.dump(event)
    end
  end
end
