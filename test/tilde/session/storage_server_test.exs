defmodule Tilde.Session.StorageServerTest do
  use TildeTest.Case, async: false

  alias Tilde.Session.Server

  test "persists newly appended events and draft state through configured storage" do
    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_test_pid, self(), fn ->
        {:ok, server} = Server.start_link(session: Tilde.session(id: "stored-session"))

        Server.append_event(server, Tilde.input_changed("draft"))
        Server.append_event(server, Tilde.input_submitted("hello"))

        assert_receive {:storage_save_state, "stored-session", "draft"}
        refute_receive {:storage_append_event, "stored-session", :input_changed, "draft"}
        assert_receive {:storage_append_event, "stored-session", :input_submitted, "hello"}
        assert_receive {:storage_save_state, "stored-session", ""}
      end)
    end)
  end

  test "persists command-generated events once" do
    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_test_pid, self(), fn ->
        {:ok, server} = Server.start_link(session: Tilde.session(id: "command-session"))

        Server.append_event(server, Tilde.input_submitted("/help"))

        assert_receive {:storage_append_event, "command-session", :input_submitted, "/help"}
        assert_receive {:storage_append_event, "command-session", :assistant_done, help_text}
        assert help_text =~ "/help"
        refute_receive {:storage_append_event, "command-session", :assistant_done, ^help_text}
      end)
    end)
  end
end
