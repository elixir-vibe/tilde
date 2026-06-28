defmodule Tilde.Session.ReviewState do
  @moduledoc """
  Stores review comment status in durable session metadata.

  The review itself is derived from workspace/Git state. Only user workflow
  decisions such as resolved/reopened comments are persisted with the session.
  """

  alias Tilde.Core.Review
  alias Tilde.Core.Session

  @metadata_key :review_statuses
  @string_metadata_key "review_statuses"

  @doc "Applies review statuses stored in the session metadata."
  @spec load(Review.t(), Session.t()) :: Review.t()
  def load(%Review{} = review, %Session{} = session) do
    Review.apply_statuses(review, statuses(session))
  end

  @doc "Stores review statuses in session metadata."
  @spec put(Session.t(), Review.t()) :: Session.t()
  def put(%Session{metadata: metadata} = session, %Review{} = review) do
    metadata =
      metadata
      |> Map.delete(@string_metadata_key)
      |> Map.put(@metadata_key, Review.dump_statuses(review))

    %{session | metadata: metadata}
  end

  @doc "Returns raw persisted review statuses from session metadata."
  @spec statuses(Session.t()) :: map()
  def statuses(%Session{metadata: metadata}) do
    Map.get(metadata, @metadata_key) || Map.get(metadata, @string_metadata_key) || %{}
  end
end
