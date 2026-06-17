defmodule Tilde.Renderer do
  @moduledoc """
  Behaviour for renderers that consume semantic Tilde structures.

  Renderers are disposable adapters. They turn `Tilde.Core.Session` or
  `Tilde.Core.Transcript` data into non-interactive target representations such as
  plain text, JSON, or ANSI iodata. LiveView remains component-based under
  `Tilde.Transport.Live` because interactive DOM rendering has a different shape
  than snapshot renderers.
  """

  @type source :: Tilde.Core.Session.t() | Tilde.Core.Transcript.t()

  @callback render(source(), keyword()) :: term()
end
