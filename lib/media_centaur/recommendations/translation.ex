defmodule MediaCentaur.Recommendations.Translation do
  @moduledoc """
  The anti-corruption layer between Nostr events and recommendation
  records. Kind 32160 (addressable): `d` = `tmdb:<media_type>:<tmdb_id>`;
  content = JSON `{"title": <TMDB.Title fields>, "note": string|null}`.
  An optional `p` (recipient) tag is defined by the spec for directed
  recommendations and is never set here.

  Both directions are pure and know nothing about relays or storage:
  `to_event/3` builds the unsigned event a caller signs, `from_event/1`
  shape-checks an already-*verified* event into record attrs. The
  address and the content snapshot must agree on identity — a mismatch
  is a rejected event, not a reconciled one.
  """

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.TMDB.Title

  @kind 32_160

  @doc "The event kind recommendations use."
  @spec kind() :: non_neg_integer()
  def kind, do: @kind

  @doc "The address tag value for a title."
  @spec address(Title.t()) :: String.t()
  def address(%Title{tmdb_id: id, media_type: type}), do: "tmdb:#{type}:#{id}"

  @doc "An unsigned recommendation event from `pubkey`."
  @spec to_event(Title.t(), String.t() | nil, String.t()) :: Event.t()
  def to_event(%Title{} = title, note, pubkey) do
    Event.new(%{
      pubkey: pubkey,
      created_at: System.os_time(:second),
      kind: @kind,
      tags: [["d", address(title)]],
      content: Jason.encode!(%{"title" => title_map(title), "note" => blank_to_nil(note)})
    })
  end

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
          {:ok, attrs()} | {:error, :wrong_kind | :bad_address | :bad_content | :identity_mismatch}
  def from_event(%Event{kind: @kind} = event) do
    with {:ok, {media_type, tmdb_id}} <- parse_address(Event.tag_value(event, "d")),
         {:ok, %{"title" => title_attrs} = content} <- decode_content(event.content),
         {:ok, title} <- build_title(title_attrs),
         :ok <- match_identity(title, media_type, tmdb_id) do
      {:ok,
       %{
         event_id: event.id,
         author_pubkey: event.pubkey,
         tmdb_id: tmdb_id,
         media_type: media_type,
         title: title,
         note: blank_to_nil(content["note"]),
         recommended_at: DateTime.from_unix!(event.created_at),
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

  defp decode_content(content) do
    case Jason.decode(content) do
      {:ok, %{"title" => %{}} = map} -> {:ok, map}
      _other -> {:error, :bad_content}
    end
  end

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
