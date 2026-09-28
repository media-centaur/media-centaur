defmodule MediaCentaur.DiscoveryRows do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Enriched activity rows in the shape `DiscoveryLive` assigns — the
  `Activities.activity_row/0` (`activity` and its `author`, a
  `Social.Person`) plus the page's joins (poster and library owner,
  watchlist membership, acquisition state) — for the pure projection
  and component tests. `person/2` and `own_person/1` build the authors.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title

  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @own_pubkey "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

  @doc """
  A friend as the reader sees them, under the reader's name for them;
  nil is a friend without an override. `published_name:` is what the
  friend's key published; `avatar_url:` its avatar; `show_avatar:` the
  reader's switch (default true); `published_hue:` the hue the key
  published; `hue_override:` the reader's hue for them.
  """
  @spec person(String.t() | nil, keyword()) :: Person.t()
  def person(name, opts \\ []) when is_binary(name) or is_nil(name) do
    show_avatar = Keyword.get(opts, :show_avatar, true)

    %Person{
      pubkey: Keyword.get(opts, :pubkey, @friend_pubkey),
      name_override: name,
      published_name: Keyword.get(opts, :published_name),
      # As `Social.person_for/2` builds it: a hidden avatar has no URL.
      avatar_url: if(show_avatar, do: Keyword.get(opts, :avatar_url)),
      show_avatar: show_avatar,
      published_hue: Keyword.get(opts, :published_hue),
      hue_override: Keyword.get(opts, :hue_override),
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  @doc "The reader as a person."
  @spec own_person(String.t()) :: Person.t()
  def own_person(pubkey \\ @own_pubkey), do: %Person{pubkey: pubkey, own?: true}

  @doc """
  One enriched row. `author:` is the Person (a friend named Sample
  Friend unless given); the activity's `author_pubkey` follows the
  author unless the activity overrides set one.
  """
  def activity_row(overrides \\ %{}) do
    activity = Map.get(overrides, :activity, %{})
    author = Map.get(overrides, :author, person("Sample Friend"))
    tmdb_id = Map.get(activity, :tmdb_id, 777)
    media_type = Map.get(activity, :media_type, :movie)

    title =
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: Map.get(activity, :name, "Sample Movie #{tmdb_id}")
      })

    %{
      activity:
        struct!(
          Activity,
          Map.merge(
            %{
              id:
                Map.get(
                  activity,
                  :id,
                  "activity-#{tmdb_id}-#{Map.get(activity, :kind, :review)}"
                ),
              kind: :review,
              sentiment: :like,
              text: nil,
              episode: nil,
              tmdb_id: tmdb_id,
              media_type: media_type,
              title: title,
              author_pubkey: author.pubkey,
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            Map.delete(activity, :name)
          )
        ),
      author: author,
      poster_url: Map.get(overrides, :poster_url),
      library_owner_id: Map.get(overrides, :library_owner_id),
      rung: Map.get(overrides, :rung),
      acquisition_state: Map.get(overrides, :acquisition_state)
    }
  end
end
