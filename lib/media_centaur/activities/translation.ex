defmodule MediaCentaur.Activities.Translation do
  @moduledoc """
  The anti-corruption layer between Nostr events and activity records —
  the app's side of `docs/social-protocol.md`. Three addressable kinds
  share one address, `d` = `tmdb:<media_type>:<tmdb_id>`, and one content
  envelope, JSON `{"v": 1, "title": <TMDB.Title fields>, …}`:

  | Kind | Name | Content beyond the envelope |
  |---|---|---|
  | 32160 | Recommendation | `note` (string or null), `recommended_at` |
  | 32161 | Watched | `watched_at`, `episode` (TV only: `season_number`, `episode_number`, `name`) |
  | 32162 | Tracking | `tracked_at` |

  An optional `p` (recipient) tag is defined by the spec for directed
  recommendations and is never set here. Kind 5 (NIP-09) withdraws an
  activity of any kind: a single `a` tag naming the signer's own address.

  Both directions are pure and know nothing about relays or storage:
  `to_event/4` builds the unsigned event a caller signs, `from_event/1`
  shape-checks an already-*verified* event into record attrs. The
  address and the content snapshot must agree on identity — a mismatch
  is a rejected event, not a reconciled one.

  Two times ride on every message. The **wire time** is the event's
  `created_at`: it decides which of two copies wins, here and on the
  relay, and nothing else. The **domain time** is when the person acted
  — `recommended_at` / `watched_at` / `tracked_at` in the content, a
  `deleted_at` tag on a deletion — and is what the app orders and shows
  by (`acted_at` on the row). They coincide in practice, but readers
  never derive one from the other: an event missing its domain time gets
  the wire time as a fallback and that is all.

  Inbound strings are capped: note at 500, title name at 300, title
  overview at 2000, episode name at 300 characters; larger events are
  rejected as `:bad_content`.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.TMDB.Title

  @kinds %{recommendation: 32_160, watched: 32_161, tracking: 32_162}
  @kind_names Map.new(@kinds, fn {name, number} -> {number, name} end)
  @kind_numbers Map.values(@kinds)
  @deletion_kind 5
  @content_version 1
  @max_note 500
  @max_name 300
  @max_overview 2000

  @doc "The inbound cap on a recommendation note, in characters."
  @spec max_note_length() :: pos_integer()
  def max_note_length, do: @max_note

  @doc "The event kind number of an activity kind."
  @spec kind(Activity.kind()) :: non_neg_integer()
  def kind(name) when is_map_key(@kinds, name), do: Map.fetch!(@kinds, name)

  @doc "Every activity kind number, for a relay subscription."
  @spec kinds() :: [non_neg_integer()]
  def kinds, do: @kind_numbers

  @doc "The event kind a deletion uses (NIP-09)."
  @spec deletion_kind() :: non_neg_integer()
  def deletion_kind, do: @deletion_kind

  @doc "The address coordinate a deletion names: `<kind>:<pubkey>:tmdb:<type>:<id>`."
  @spec coordinate(Activity.kind(), String.t(), Title.media_type(), pos_integer()) :: String.t()
  def coordinate(kind, pubkey, media_type, tmdb_id),
    do: "#{kind(kind)}:#{pubkey}:tmdb:#{media_type}:#{tmdb_id}"

  @doc "The address tag value for a title."
  @spec address(Title.t()) :: String.t()
  def address(%Title{tmdb_id: id, media_type: type}), do: "tmdb:#{type}:#{id}"

  @typedoc "Unix seconds for the wire (`created_at`) and the act (`acted_at` / `deleted_at`); both default to now."
  @type times :: [
          created_at: non_neg_integer(),
          acted_at: non_neg_integer(),
          deleted_at: non_neg_integer()
        ]

  @typedoc """
  What an activity says beyond its title: a recommendation's `note`, a
  watched TV series' `episode`. A tracking activity and a watched movie
  carry nothing.
  """
  @type payload :: [note: String.t() | nil, episode: Episode.t() | nil]

  @doc """
  An unsigned activity event of `kind` from `pubkey` about `title`. The
  payload's `note` rides on a recommendation and its `episode` on a
  watched activity; either is ignored on the other kinds.
  """
  @spec to_event(Activity.kind(), Title.t(), payload(), String.t(), times()) :: Event.t()
  def to_event(kind, %Title{} = title, payload, pubkey, times \\ []) do
    now = System.os_time(:second)

    content =
      Map.merge(
        %{"v" => @content_version, "title" => title_map(title)},
        kind_content(kind, payload, Keyword.get(times, :acted_at, now))
      )

    Event.new(%{
      pubkey: pubkey,
      created_at: Keyword.get(times, :created_at, now),
      kind: kind(kind),
      tags: [["d", address(title)]],
      content: Jason.encode!(content)
    })
  end

  defp kind_content(:recommendation, payload, acted_at),
    do: %{"note" => blank_to_nil(Keyword.get(payload, :note)), "recommended_at" => acted_at}

  defp kind_content(:watched, payload, acted_at),
    do: %{"watched_at" => acted_at, "episode" => episode_map(Keyword.get(payload, :episode))}

  defp kind_content(:tracking, _payload, acted_at), do: %{"tracked_at" => acted_at}

  defp episode_map(nil), do: nil

  defp episode_map(%Episode{} = episode),
    do: %{
      "season_number" => episode.season_number,
      "episode_number" => episode.episode_number,
      "name" => episode.name
    }

  @doc """
  An unsigned deletion (kind 5) from `pubkey` withdrawing its own
  activity of `kind` at the address — the `a` tag — with the withdrawn
  event's id as an `e` tag when known (`nil` omits it: the address alone
  identifies what is withdrawn) and the time of the act as a `deleted_at`
  tag.
  """
  @spec to_deletion(
          Activity.kind(),
          String.t(),
          Title.media_type(),
          pos_integer(),
          String.t() | nil,
          times()
        ) ::
          Event.t()
  def to_deletion(kind, pubkey, media_type, tmdb_id, event_id, times \\ []) do
    now = System.os_time(:second)

    tags =
      [["a", coordinate(kind, pubkey, media_type, tmdb_id)]] ++
        if(event_id, do: [["e", event_id]], else: []) ++
        [["deleted_at", Integer.to_string(Keyword.get(times, :deleted_at, now))]]

    Event.new(%{
      pubkey: pubkey,
      created_at: Keyword.get(times, :created_at, now),
      kind: @deletion_kind,
      tags: tags,
      content: ""
    })
  end

  @type deletion_attrs :: %{
          kind: Activity.kind(),
          author_pubkey: String.t(),
          tmdb_id: pos_integer(),
          media_type: Title.media_type(),
          created_at: non_neg_integer(),
          deleted_at: DateTime.t(),
          deletion_event: map()
        }

  @doc """
  Tombstone attrs from a *verified* deletion event. Exactly one `a` tag,
  of an activity kind, whose pubkey is the signer's own; anything else
  is `:not_author` or `:bad_address`. `created_at` is the wire time;
  `deleted_at` the `deleted_at` tag, or the wire time when absent.
  """
  @spec from_deletion(Event.t()) ::
          {:ok, deletion_attrs()} | {:error, :wrong_kind | :bad_address | :not_author | :bad_content}
  def from_deletion(%Event{kind: @deletion_kind} = event) do
    with {:ok, {kind, author, media_type, tmdb_id}} <- parse_coordinate(Event.tag_value(event, "a")),
         :ok <- author_matches(author, event.pubkey),
         {:ok, deleted_at} <- parse_domain_time(tag_integer(event, "deleted_at"), event.created_at) do
      {:ok,
       %{
         kind: kind,
         author_pubkey: author,
         tmdb_id: tmdb_id,
         media_type: media_type,
         created_at: event.created_at,
         deleted_at: deleted_at,
         deletion_event: Event.to_map(event)
       }}
    end
  end

  def from_deletion(%Event{}), do: {:error, :wrong_kind}

  defp parse_coordinate(coordinate) when is_binary(coordinate) do
    with [kind_text, pubkey, address] <- String.split(coordinate, ":", parts: 3),
         {kind_number, ""} <- Integer.parse(kind_text),
         %{^kind_number => kind} <- @kind_names,
         {:ok, {media_type, tmdb_id}} <- parse_address(address) do
      {:ok, {kind, pubkey, media_type, tmdb_id}}
    else
      _other -> {:error, :bad_address}
    end
  end

  defp parse_coordinate(_absent), do: {:error, :bad_address}

  defp author_matches(author, author), do: :ok
  defp author_matches(_author, _signer), do: {:error, :not_author}

  # A tag value is a string on the wire; anything but an integer in it is
  # malformed, and an absent tag is `nil` (the wire time stands in).
  defp tag_integer(event, name) do
    case Event.tag_value(event, name) do
      nil ->
        nil

      text ->
        case Integer.parse(text) do
          {int, ""} -> int
          _other -> :malformed
        end
    end
  end

  @type attrs :: %{
          kind: Activity.kind(),
          event_id: String.t(),
          author_pubkey: String.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          note: String.t() | nil,
          episode: Episode.t() | nil,
          created_at: non_neg_integer(),
          acted_at: DateTime.t(),
          raw_event: map()
        }

  @doc """
  Record attrs from a *verified* event of any activity kind; shape and
  address checks only. `created_at` is the wire time; `acted_at` the
  kind's domain-time field in the content, or the wire time when absent.
  """
  @spec from_event(Event.t()) ::
          {:ok, attrs()}
          | {:error,
             :wrong_kind | :bad_address | :bad_content | :identity_mismatch | :unsupported_version}
  def from_event(%Event{kind: number} = event) when number in @kind_numbers do
    kind = Map.fetch!(@kind_names, number)

    with {:ok, {media_type, tmdb_id}} <- parse_address(Event.tag_value(event, "d")),
         {:ok, %{"title" => title_attrs} = content} <- decode_content(event.content),
         :ok <- check_version(content),
         :ok <- check_length(title_attrs["name"], @max_name),
         :ok <- check_length(title_attrs["overview"], @max_overview),
         {:ok, title} <- build_title(title_attrs),
         :ok <- match_identity(title, media_type, tmdb_id),
         {:ok, payload} <- kind_payload(kind, content, media_type),
         {:ok, acted_at} <- parse_domain_time(content[acted_at_field(kind)], event.created_at) do
      {:ok,
       Map.merge(payload, %{
         kind: kind,
         event_id: event.id,
         author_pubkey: event.pubkey,
         tmdb_id: tmdb_id,
         media_type: media_type,
         title: title,
         created_at: event.created_at,
         acted_at: acted_at,
         raw_event: Event.to_map(event)
       })}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp acted_at_field(:recommendation), do: "recommended_at"
  defp acted_at_field(:watched), do: "watched_at"
  defp acted_at_field(:tracking), do: "tracked_at"

  # The kind's own fields, checked and shaped. Anything the kind does not
  # carry is nil on the row.
  defp kind_payload(:recommendation, content, _media_type) do
    with :ok <- check_length(content["note"], @max_note) do
      {:ok, %{note: blank_to_nil(content["note"]), episode: nil}}
    end
  end

  defp kind_payload(:watched, content, media_type) do
    with {:ok, episode} <- build_episode(content["episode"], media_type) do
      {:ok, %{note: nil, episode: episode}}
    end
  end

  defp kind_payload(:tracking, _content, _media_type), do: {:ok, %{note: nil, episode: nil}}

  # A watched movie names no episode; a watched TV series may. Anything
  # else in the slot is malformed.
  defp build_episode(nil, _media_type), do: {:ok, nil}

  defp build_episode(attrs, :tv_series) when is_map(attrs) do
    with :ok <- check_length(attrs["name"], @max_name) do
      apply_changeset(Episode.changeset(attrs))
    end
  end

  defp build_episode(_attrs, _media_type), do: {:error, :bad_content}

  defp parse_address("tmdb:movie:" <> id), do: parse_id(:movie, id)
  defp parse_address("tmdb:tv_series:" <> id), do: parse_id(:tv_series, id)
  defp parse_address(_other), do: {:error, :bad_address}

  defp parse_id(type, id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> {:ok, {type, int}}
      _other -> {:error, :bad_address}
    end
  end

  # The act's time from the payload, the wire time standing in when the
  # payload has none. A relay can send any integer it likes;
  # `DateTime.from_unix!/1` raises past `~U[9999-12-31 23:59:59Z]`, and
  # this is untrusted input — as is a value that is not an integer at all.
  defp parse_domain_time(nil, created_at), do: parse_domain_time(created_at, created_at)

  defp parse_domain_time(seconds, _created_at) when is_integer(seconds) do
    case DateTime.from_unix(seconds) do
      {:ok, at} -> {:ok, at}
      {:error, _reason} -> {:error, :bad_content}
    end
  end

  defp parse_domain_time(_other, _created_at), do: {:error, :bad_content}

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
  # value is left for the changeset (or `blank_to_nil/1`) to reject.
  defp check_length(value, max) when is_binary(value) do
    if String.length(value) <= max, do: :ok, else: {:error, :bad_content}
  end

  defp check_length(_value, _max), do: :ok

  defp build_title(attrs) when is_map(attrs), do: apply_changeset(Title.changeset(attrs))

  defp apply_changeset(changeset) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, struct} -> {:ok, struct}
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
