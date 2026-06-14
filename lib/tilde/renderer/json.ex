defmodule Tilde.Renderer.JSON do
  @moduledoc """
  JSON-compatible map renderer for semantic transcripts.
  """

  @behaviour Tilde.Renderer

  alias Tilde.{Block, Session, Stream, Transcript}

  @impl true
  def render(source, opts \\ [])

  def render(%Session{transcript: transcript, statuses: statuses, metadata: metadata}, opts) do
    transcript
    |> render(opts)
    |> Map.merge(%{statuses: statuses, metadata: metadata})
  end

  def render(%Transcript{} = transcript, _opts) do
    %{
      blocks: Enum.map(transcript.blocks, &block_to_map/1),
      statuses: transcript.statuses,
      metadata: transcript.metadata
    }
  end

  defp block_to_map(%Block{} = block) do
    %{
      id: block.id,
      kind: block.kind,
      role: block.role,
      format: block.format,
      source: block.source,
      name: block.name,
      status: block.status,
      args: block.args,
      streams: Enum.map(block.streams, &stream_to_map/1),
      result: block.result,
      display: Map.from_struct(block.display),
      metadata: block.metadata
    }
  end

  defp stream_to_map(%Stream{} = stream) do
    %{
      id: stream.id,
      kind: stream.kind,
      chunks: stream.chunks,
      text: Stream.text(stream),
      line_count: Stream.line_count(stream),
      byte_count: Stream.byte_count(stream),
      complete?: stream.complete?
    }
  end
end
