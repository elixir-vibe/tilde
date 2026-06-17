defmodule Tilde.Session.LoaderTest do
  use TildeTest.Case, async: false

  alias Tilde.Session.Loader

  test "loads a persisted session when storage adapter is configured" do
    stored =
      Tilde.session(id: "stored")
      |> Session.append_event(Tilde.input_submitted("remembered"))
      |> Session.append_event(Tilde.input_changed("draft"))

    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_load_session, fn "stored" -> stored end, fn ->
        loaded = Loader.load_or_new("stored", new: fn -> Tilde.session(id: "fresh") end)

        assert loaded.id == "stored"
        assert latest_user_sources(loaded) == ["remembered"]
        assert loaded.input.value == "draft"
      end)
    end)
  end

  test "creates a fresh session when storage is disabled" do
    with_application_env(:storage_adapter, nil, fn ->
      assert %{id: "fresh"} =
               Loader.load_or_new("stored", new: fn -> Tilde.session(id: "fresh") end)
    end)
  end
end
