defmodule MediaCentaur.Activities.ReviewedByFriendsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory, only: [build_actor: 0]

  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbStubs

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @other_secret Secret.wrap(String.duplicate("0", 63) <> "5")
  @other_pubkey "2f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4"

  defp title(tmdb_id, name), do: Title.new!(%{tmdb_id: tmdb_id, media_type: :movie, name: name})

  defp ingest(kind, title, opts, pubkey, secret, acted_at) do
    event =
      Event.sign(
        Translation.to_event(kind, title, opts, pubkey, acted_at: acted_at, created_at: acted_at),
        secret
      )

    {:ok, _activity} = Activities.ingest(event)
    await_supervised_tasks()
  end

  setup context do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache(context)
    Identity.ensure()
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    {:ok, _other} = Social.add_friend(@other_pubkey, "Other Friend")
    :ok
  end

  test "one entry per title a friend reviewed, newest review first; the reader's own review and a bare watched act are not reviews by friends" do
    movie_a = title(901, "Movie A")
    movie_b = title(902, "Movie B")
    movie_c = title(903, "Movie C")
    movie_d = title(904, "Movie D")

    ingest(
      :review,
      movie_a,
      [sentiment: :like, text: "fine"],
      @friend_pubkey,
      @friend_secret,
      1_700_000_100
    )

    ingest(
      :review,
      movie_b,
      [sentiment: :love, text: "great"],
      @friend_pubkey,
      @friend_secret,
      1_700_000_300
    )

    ingest(
      :review,
      movie_a,
      [sentiment: :dislike, text: "no"],
      @other_pubkey,
      @other_secret,
      1_700_000_200
    )

    ingest(:watched, movie_c, [], @friend_pubkey, @friend_secret, 1_700_000_400)
    {:ok, _own} = Activities.review(movie_d, :like, "mine", build_actor())
    await_supervised_tasks()

    assert [
             %{ref: {902, :movie}, title: %Title{name: "Movie B"}},
             %{ref: {901, :movie}, title: %Title{name: "Movie A"}, reviewed_at: reviewed_at}
           ] = Activities.reviewed_by_friends(40)

    assert DateTime.to_unix(reviewed_at) == 1_700_000_200
  end

  test "a hidden person's reviews are not shown, and the limit caps the list" do
    ingest(:review, title(901, "Movie A"), [text: "a"], @friend_pubkey, @friend_secret, 1_700_000_100)
    ingest(:review, title(902, "Movie B"), [text: "b"], @other_pubkey, @other_secret, 1_700_000_200)
    {:ok, _contact} = Social.set_hidden(@other_pubkey, true)

    assert [%{ref: {901, :movie}}] = Activities.reviewed_by_friends(40)

    {:ok, _contact} = Social.set_hidden(@other_pubkey, false)
    assert [%{ref: {902, :movie}}] = Activities.reviewed_by_friends(1)
  end
end
