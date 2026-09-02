defmodule MediaCentaur.Recommendations.TranslationTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.Secret
  alias MediaCentaur.TMDB.Title

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp title do
    Title.new!(%{
      tmdb_id: 603,
      media_type: :movie,
      name: "Sample Movie",
      year: "1999",
      release_date: ~D[1999-03-31],
      poster_path: "/p.jpg",
      overview: "A sample overview."
    })
  end

  test "to_event builds an addressable kind-32160 event with the title snapshot and note" do
    event = Translation.to_event(title(), "Watch it twice.", @pubkey)

    assert event.kind == 32_160
    assert event.pubkey == @pubkey
    assert Event.tag_value(event, "d") == "tmdb:movie:603"
    refute Event.tag_value(event, "p")

    assert %{
             "title" => %{
               "tmdb_id" => 603,
               "media_type" => "movie",
               "name" => "Sample Movie",
               "release_date" => "1999-03-31"
             },
             "note" => "Watch it twice."
           } = Jason.decode!(event.content)
  end

  test "a nil note serializes as null" do
    assert %{"note" => nil} = Jason.decode!(Translation.to_event(title(), nil, @pubkey).content)
  end

  test "from_event round-trips a signed event into attrs" do
    signed = Event.sign(Translation.to_event(title(), "Watch it twice.", @pubkey), @secret)

    assert {:ok, attrs} = Translation.from_event(signed)
    assert attrs.event_id == signed.id
    assert attrs.author_pubkey == @pubkey
    assert attrs.tmdb_id == 603
    assert attrs.media_type == :movie

    assert %Title{name: "Sample Movie", release_date: ~D[1999-03-31], poster_path: "/p.jpg"} =
             attrs.title

    assert attrs.note == "Watch it twice."
    assert attrs.recommended_at == DateTime.from_unix!(signed.created_at)
    assert attrs.raw_event == Event.to_map(signed)
  end

  test "from_event rejects the wrong kind, a bad address, mismatched identity, and junk content" do
    good = Event.sign(Translation.to_event(title(), nil, @pubkey), @secret)

    assert {:error, :wrong_kind} = Translation.from_event(%{good | kind: 1})
    assert {:error, :bad_address} = Translation.from_event(%{good | tags: [["d", "imdb:tt1"]]})
    assert {:error, :bad_address} = Translation.from_event(%{good | tags: []})

    assert {:error, :identity_mismatch} =
             Translation.from_event(%{good | tags: [["d", "tmdb:movie:604"]]})

    assert {:error, :bad_content} = Translation.from_event(%{good | content: "not json"})

    assert {:error, :bad_content} =
             Translation.from_event(%{
               good
               | content: ~s({"title": {"tmdb_id": 603, "media_type": "movie"}})
             })

    # `DateTime.from_unix!/1` raises for a value past `~U[9999-12-31
    # 23:59:59Z]` — a relay can send any `created_at` it likes, so this must
    # be rejected, not crash the caller. Unsigned: `from_event/1` never
    # verifies signatures.
    assert {:error, :bad_content} =
             Translation.from_event(%{good | created_at: 253_402_300_800})
  end

  test "from_event rejects a note over the cap and accepts one at the cap" do
    over_cap = String.duplicate("n", 501)
    at_cap = String.duplicate("n", 500)

    over_event = Event.sign(Translation.to_event(title(), over_cap, @pubkey), @secret)
    at_event = Event.sign(Translation.to_event(title(), at_cap, @pubkey), @secret)

    assert {:error, :bad_content} = Translation.from_event(over_event)
    assert {:ok, %{note: ^at_cap}} = Translation.from_event(at_event)
  end

  test "from_event rejects a title name over the cap" do
    long_title = Title.new!(%{tmdb_id: 603, media_type: :movie, name: String.duplicate("n", 301)})
    event = Event.sign(Translation.to_event(long_title, nil, @pubkey), @secret)

    assert {:error, :bad_content} = Translation.from_event(event)
  end

  test "from_event rejects a title overview over the cap" do
    long_title =
      Title.new!(%{
        tmdb_id: 603,
        media_type: :movie,
        name: "Sample Movie",
        overview: String.duplicate("n", 2001)
      })

    event = Event.sign(Translation.to_event(long_title, nil, @pubkey), @secret)

    assert {:error, :bad_content} = Translation.from_event(event)
  end

  test "max_note_length/0 is the inbound note cap" do
    assert Translation.max_note_length() == 500
  end
end
