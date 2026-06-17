defmodule TildeTest.Case do
  @moduledoc "Shared case template and helpers for Tilde tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case, async: false

      import Phoenix.LiveViewTest
      import Plug.Test
      import TildeTest.Case
      import TildeTest.SessionAssertions

      alias Tilde.Core.{
        Block,
        Choice,
        Display,
        Input,
        Run,
        Session,
        Stream,
        Transcript
      }

      alias Tilde.Renderer
      alias Tilde.Tool.ViewModel
    end
  end

  import ExUnit.Assertions

  alias Tilde.Core.{Block, Session}

  def with_application_env(key, value, fun) do
    previous = Application.get_env(:tilde, key)
    Application.put_env(:tilde, key, value)

    result = fun.()
    restore_application_env(key, previous)
    result
  end

  def asset_css(path) do
    File.read!(Path.join([File.cwd!(), "assets", "css", "tilde", path]))
  end

  def strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
  end

  def strip_html(text), do: Regex.replace(~r/<[^>]+>/, text, "")

  def wait_for_sources(session_id, predicate) do
    receive do
      {:tilde_session_updated, ^session_id, %Session{transcript: %{blocks: blocks}}} ->
        sources = Enum.map(blocks, & &1.source)
        if predicate.(sources), do: sources, else: wait_for_sources(session_id, predicate)
    after
      1_000 -> flunk("timed out waiting for session #{session_id}")
    end
  end

  def latest_user_sources(%Session{} = session) do
    session.transcript.blocks
    |> Enum.filter(&match?(%Block{kind: :message, role: :user}, &1))
    |> Enum.map(& &1.source)
  end

  def restore_application_env(key, nil), do: Application.delete_env(:tilde, key)
  def restore_application_env(key, previous), do: Application.put_env(:tilde, key, previous)

  def restore_system_env(key, nil), do: System.delete_env(key)
  def restore_system_env(key, previous), do: System.put_env(key, previous)
end
