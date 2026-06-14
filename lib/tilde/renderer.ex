defmodule Tilde.Renderer do
  @moduledoc """
  Behaviour for renderers that consume semantic Tilde structures.

  Renderers are disposable adapters. They turn `Tilde.Session` or
  `Tilde.Transcript` data into a target representation such as plain text, JSON,
  ANSI iodata, or DOM components.
  """

  @type source :: Tilde.Session.t() | Tilde.Transcript.t()

  @callback render(source(), keyword()) :: term()
end
