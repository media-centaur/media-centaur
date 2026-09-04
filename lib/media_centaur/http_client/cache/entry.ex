defmodule MediaCentaur.HttpClient.Cache.Entry do
  @moduledoc """
  One stored response: the raw body, what is needed to serve it again,
  and what is needed to revalidate it.

  The body is kept as the wire binary, not the decoded term. A large
  binary is reference-counted and shared by every reader; a decoded
  map would be copied out of ETS on every hit. Decoding happens in the
  reader's own Req pipeline, exactly as for a response off the wire.

  Times are `System.monotonic_time(:millisecond)`. An entry is *fresh*
  while `fresh_until` is ahead of now; past that it is *stale* and is
  served only after revalidation. `max_age_ms` is remembered so a 304
  without its own `Cache-Control` can renew by the same span.
  """

  alias MediaCentaur.HttpClient.Cache.{Freshness, Key}

  @enforce_keys [:key, :body, :content_type, :etag, :fresh_until, :max_age_ms, :stored_at]
  defstruct [:key, :body, :content_type, :etag, :fresh_until, :max_age_ms, :stored_at]

  @type t :: %__MODULE__{
          key: Key.t(),
          body: binary(),
          content_type: String.t(),
          etag: String.t() | nil,
          fresh_until: integer(),
          max_age_ms: non_neg_integer(),
          stored_at: integer()
        }

  @doc """
  An entry for a 200 response with a raw binary body, or `nil` when the
  response must not be stored.
  """
  @spec from_response(Key.t(), Req.Response.t(), integer()) :: t() | nil
  def from_response(key, %Req.Response{status: 200, body: body} = response, now) when is_binary(body) do
    etag = List.first(Req.Response.get_header(response, "etag"))

    case Freshness.max_age(response) do
      nil ->
        nil

      # Stale at once and nothing to revalidate with: every use would be a
      # plain miss, so the entry would only ever take up room.
      0 when is_nil(etag) ->
        nil

      seconds ->
        %__MODULE__{
          key: key,
          body: body,
          content_type:
            List.first(Req.Response.get_header(response, "content-type")) || "application/json",
          etag: etag,
          fresh_until: now + seconds * 1000,
          max_age_ms: seconds * 1000,
          stored_at: now
        }
    end
  end

  def from_response(_key, _response, _now), do: nil

  @doc "The entry renewed by a 304, fresh again from `now`."
  @spec renew(t(), Req.Response.t(), integer()) :: t()
  def renew(%__MODULE__{} = entry, %Req.Response{status: 304} = response, now) do
    max_age_ms =
      case Freshness.max_age(response) do
        nil -> entry.max_age_ms
        seconds -> seconds * 1000
      end

    %{entry | fresh_until: now + max_age_ms, max_age_ms: max_age_ms, stored_at: now}
  end

  @doc "A 200 response carrying the stored body, ready for the reader's response steps."
  @spec to_response(t()) :: Req.Response.t()
  def to_response(%__MODULE__{} = entry) do
    Req.Response.new(
      status: 200,
      headers: %{"content-type" => [entry.content_type]},
      body: entry.body
    )
  end

  @doc "Whether the entry may be served without revalidation at `now`."
  @spec fresh?(t(), integer()) :: boolean()
  def fresh?(%__MODULE__{fresh_until: fresh_until}, now), do: now < fresh_until
end
