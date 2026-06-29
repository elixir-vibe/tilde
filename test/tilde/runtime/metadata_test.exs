defmodule Tilde.Runtime.MetadataTest do
  use TildeTest.Case, async: true

  alias Tilde.Runtime.Metadata

  test "keeps scalar metadata" do
    assert Metadata.sanitize(%{
             atom: :value,
             binary: "value",
             integer: 1,
             float: 1.5,
             boolean: false
           }) == %{
             atom: :value,
             binary: "value",
             integer: 1,
             float: 1.5,
             boolean: false
           }
  end

  test "drops runtime-only values" do
    sanitized =
      Metadata.sanitize(%{
        pid: self(),
        ref: make_ref(),
        callback: fn -> :unsafe end,
        kept: "safe"
      })

    assert sanitized == %{kept: "safe"}
  end

  test "drops unsafe map keys and sanitizes nested values" do
    sanitized =
      Metadata.sanitize(%{
        :safe => %{nested: self(), kept: "value"},
        self() => "pid key",
        make_ref() => "ref key",
        {:tuple, :key} => "tuple key"
      })

    assert sanitized == %{safe: %{kept: "value"}}
  end

  test "stringifies structs instead of preserving raw structs" do
    datetime = ~U[2026-06-29 10:00:00Z]

    assert %{generated_at: generated_at} = Metadata.sanitize(%{generated_at: datetime})
    assert is_binary(generated_at)
    assert generated_at == inspect(datetime)
  end

  test "recurses through lists and tuples" do
    sanitized =
      Metadata.sanitize(%{
        values: ["safe", self(), {:ok, make_ref(), "kept"}, %{pid: self(), kept: true}]
      })

    assert sanitized == %{values: ["safe", [:ok, "kept"], %{kept: true}]}
  end
end
