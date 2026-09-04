defmodule MediaCentaur.Recommendations.Translation do
  @moduledoc """
  The anti-corruption layer between Nostr events and recommendation
  records — the app's side of `docs/social-protocol.md`. Kind 32160
  (addressable): `d` = `tmdb:<media_type>:<tmdb_id>`; content = JSON
  `{"v": 1, "title": <TMDB.Title fields>, "note": string|null}`. An
  optional `p` (recipient) tag is defined by the spec for directed
  recommendations and is never set here. Kind 5 (NIP-09) withdraws one:
  a single `a` tag naming the signer's own recommendation address.

  Both directions are pure and know nothing about relays or storage:
  `to_event/3` builds the unsigned event a caller signs, `from_event/1`
  shape-checks an already-*verified* event into record attrs. The
  address and the content snapshot must agree on identity — a mismatch
  is a rejected event, not a reconciled one.

  Inbound strings are capped: note at 500, title name at 300, title
  overview at 2000 characters; larger events are rejected as
  `:bad_content`.
  """

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.TMDB.Title

  @kind 32_160
  @deletion_kind 5
  @content_version 1
  @max_note 500
  @max_name 300
  @max_overview 2000

  @doc "The inbound cap on a recommendation note, in characters."
  @spec max_note_length() :: pos_integer()
  def max_note_length, do: @max_note

  @doc "The event kind recommendations use."
  @spec kind() :: non_neg_integer()
  def kind, do: @kind

  @doc "The event kind a deletion uses (NIP-09)."
  @spec deletion_kind() :: non_neg_integer()
  def deletion_kind, do: @deletion_kind

  @doc "The address coordinate a deletion names: `32160:<pubkey>:tmdb:<type>:<id>`."
  @spec coordinate(String.t(), Title.media_type(), pos_integer()) :: String.t()
  def coordinate(pubkey, media_type, tmdb_id), do: "#{@kind}:#{pubkey}:tmdb:#{media_type}:#{tmdb_id}"

  @doc "The address tag value for a title."
  @spec address(Title.t()) :: String.t()
  def address(%Title{tmdb_id: id, media_type: type}), do: "tmdb:#{type}:#{id}"

  @doc "An unsigned recommendation event from `pubkey`, stamped `created_at` (now by default)."
  @spec to_event(Title.t(), String.t() | nil, String.t(), non_neg_integer()) :: Event.t()
  def to_event(%Title{} = title, note, pubkey, created_at \\ System.os_time(:second)) do
    Event.new(%{
      pubkey: pubkey,
      created_at: created_at,
      kind: @kind,
      tags: [["d", address(title)]],
      content:
        Jason.encode!(%{
          "v" => @content_version,
          "title" => title_map(title),
          "note" => blank_to_nil(note)
        })
    })
  end

  @doc """
  An unsigned deletion (kind 5) from `pubkey` withdrawing its own
  recommendation at the address — the `a` tag — with the withdrawn
  event's id as an `e` tag when known (`nil` omits it: the address alone
  identifies what is withdrawn). Stamped `created_at`, now by default.
  """
  @spec to_deletion(
          String.t(),
          Title.media_type(),
          pos_integer(),
          String.t() | nil,
          non_neg_integer()
        ) :: Event.t()
  def to_deletion(pubkey, media_type, tmdb_id, event_id, created_at \\ System.os_time(:second)) do
    tags =
      [["a", coordinate(pubkey, media_type, tmdb_id)]] ++ if(event_id, do: [["e", event_id]], else: [])

    Event.new(%{
      pubkey: pubkey,
      created_at: created_at,
      kind: @deletion_kind,
      tags: tags,
      content: ""
    })
  end

  @type deletion_attrs :: %{
          author_pubkey: String.t(),
          tmdb_id: pos_integer(),
          media_type: Title.media_type(),
          deleted_at: DateTime.t(),
          deletion_event: map()
        }

  @doc """
  Tombstone attrs from a *verified* deletion event. Exactly one `a` tag,
  kind 32160, whose pubkey is the signer's own; anything else is
  `:not_author` or `:bad_address`.
  """
  @spec from_deletion(Event.t()) ::
          {:ok, deletion_attrs()} | {:error, :wrong_kind | :bad_address | :not_author | :bad_content}
  def from_deletion(%Event{kind: @deletion_kind} = event) do
    with {:ok, {author, media_type, tmdb_id}} <- parse_coordinate(Event.tag_value(event, "a")),
         :ok <- author_matches(author, event.pubkey),
         {:ok, deleted_at} <- parse_created_at(event.created_at) do
      {:ok,
       %{
         author_pubkey: author,
         tmdb_id: tmdb_id,
         media_type: media_type,
         deleted_at: deleted_at,
         deletion_event: Event.to_map(event)
       }}
    end
  end

  def from_deletion(%Event{}), do: {:error, :wrong_kind}

  defp parse_coordinate(coordinate) when is_binary(coordinate) do
    with [kind, pubkey, address] <- String.split(coordinate, ":", parts: 3),
         true <- kind == Integer.to_string(@kind),
         {:ok, {media_type, tmdb_id}} <- parse_address(address) do
      {:ok, {pubkey, media_type, tmdb_id}}
    else
      _other -> {:error, :bad_address}
    end
  end

  defp parse_coordinate(_absent), do: {:error, :bad_address}

  defp author_matches(author, author), do: :ok
  defp author_matches(_author, _signer), do: {:error, :not_author}

  @type attrs :: %{
          event_id: String.t(),
          author_pubkey: String.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          note: String.t() | nil,
          recommended_at: DateTime.t(),
          raw_event: map()
        }

  @doc "Record attrs from a *verified* event; shape and address checks only."
  @spec from_event(Event.t()) ::
          {:ok, attrs()}
          | {:error,
             :wrong_kind | :bad_address | :bad_content | :identity_mismatch | :unsupported_version}
  def from_event(%Event{kind: @kind} = event) do
    with {:ok, {media_type, tmdb_id}} <- parse_address(Event.tag_value(event, "d")),
         {:ok, %{"title" => title_attrs} = content} <- decode_content(event.content),
         :ok <- check_version(content),
         :ok <- check_length(content["note"], @max_note),
         :ok <- check_length(title_attrs["name"], @max_name),
         :ok <- check_length(title_attrs["overview"], @max_overview),
         {:ok, title} <- build_title(title_attrs),
         :ok <- match_identity(title, media_type, tmdb_id),
         {:ok, recommended_at} <- parse_created_at(event.created_at) do
      {:ok,
       %{
         event_id: event.id,
         author_pubkey: event.pubkey,
         tmdb_id: tmdb_id,
         media_type: media_type,
         title: title,
         note: blank_to_nil(content["note"]),
         recommended_at: recommended_at,
         raw_event: Event.to_map(event)
       }}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp parse_address("tmdb:movie:" <> id), do: parse_id(:movie, id)
  defp parse_address("tmdb:tv_series:" <> id), do: parse_id(:tv_series, id)
  defp parse_address(_other), do: {:error, :bad_address}

  defp parse_id(type, id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> {:ok, {type, int}}
      _other -> {:error, :bad_address}
    end
  end

  # A relay can send any `created_at` it likes; `DateTime.from_unix!/1`
  # raises past `~U[9999-12-31 23:59:59Z]`, and this is untrusted input.
  defp parse_created_at(created_at) do
    case DateTime.from_unix(created_at) do
      {:ok, at} -> {:ok, at}
      {:error, _reason} -> {:error, :bad_content}
    end
  end

  # Absent means 1 (events written before the field existed). Fields
  # can be added without a bump; a bump marks a change of meaning, and a
  # reader that does not know the version drops the event.
  defp check_version(%{"v" => version}) when version in [@content_version], do: :ok
  defp check_version(%{"v" => _unknown}), do: {:error, :unsupported_version}
  defp check_version(_content), do: :ok

  defp decode_content(content) do
    case Jason.decode(content) do
      {:ok, %{"title" => %{}} = map} -> {:ok, map}
      _other -> {:error, :bad_content}
    end
  end

  # A relay can send a string of any length in these slots; a non-string
  # value is left for `build_title/1` (or `blank_to_nil/1`) to reject.
  defp check_length(value, max) when is_binary(value) do
    if String.length(value) <= max, do: :ok, else: {:error, :bad_content}
  end

  defp check_length(_value, _max), do: :ok

  defp build_title(attrs) when is_map(attrs) do
    case Ecto.Changeset.apply_action(Title.changeset(attrs), :insert) do
      {:ok, title} -> {:ok, title}
      {:error, _changeset} -> {:error, :bad_content}
    end
  end

  defp match_identity(%Title{tmdb_id: id, media_type: type}, type, id), do: :ok
  defp match_identity(_title, _type, _id), do: {:error, :identity_mismatch}

  # The wire snapshot: every `Title` field, string-keyed, with dates and
  # atoms flattened to the strings `Title.changeset/2` casts back.
  defp title_map(%Title{} = title) do
    title
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), dump(value)} end)
  end

  defp dump(%Date{} = date), do: Date.to_iso8601(date)

  defp dump(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom),
    do: Atom.to_string(atom)

  defp dump(other), do: other

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(string) when is_binary(string), do: if(String.trim(string) != "", do: string)
  # A relay may send anything in the note slot; anything that is not a
  # string is not a note.
  defp blank_to_nil(_other), do: nil
end
