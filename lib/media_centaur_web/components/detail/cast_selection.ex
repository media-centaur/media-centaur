defmodule MediaCentaurWeb.Components.Detail.CastSelection do
  @moduledoc """
  Pure selection rules for the Cast view — which cast members render,
  in what order, and in which section. No rendering; `CastPanel` owns
  the markup and calls these, so the rules are tested directly rather
  than through markup.

  ## Ordering

  `order_by_appearances/1` puts the people who actually carried the show
  first: descending `total_episode_count` (TMDB `aggregate_credits`),
  billing `order` as the tiebreak. Movie casts carry no counts, so the
  same sort degrades to plain billing order.

  ## Sections

  `partition_by_membership/2` splits the cast against an episode's
  `cast_person_ids` membership set (see `Library.Episode`): members lead,
  everyone else follows, both sides appearance-ordered.

  ## Paging

  At most `limit` cards render at once, `page_size/0` (24) at first —
  TMDB aggregate casts for long-running series run into the hundreds.
  The host LiveView owns the limit (`EntityModal`'s `cast_limit`), bumps
  it on `show_more_cast`, and resets it on entity switch alongside the
  filter. The limit applies **after** filtering: filtering searches the
  whole cast because the point is to find someone billed 300th.

  ## Why the filter is a server round-trip

  It used to be client-side. Every cast member was rendered, everything
  past the cap carrying `display: none`, so a JS hook could toggle
  visibility per keystroke — measured at **1.6 MB of HTML for one
  899-member series**, to show 24 cards. Selection now happens here on
  the server, which is where the cast already is; `phx-debounce` keeps
  it to one round-trip per pause, imperceptible over a local WebSocket.
  """

  # Cast cards added per page — the initial render and each Show more click.
  @page_size 24

  # Billing rank for entries without an `order` — sorts after any billed
  # entry with the same appearance count.
  @unbilled_order 1_000_000

  @doc "Cast cards per page — the initial limit and the Show more increment."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc """
  The cast in display order: most appearances first
  (`total_episode_count` descending), billing `order` as tiebreak.
  Uncounted entries (movies, pre-count embeds) sort after counted ones.
  """
  @spec order_by_appearances([map()]) :: [map()]
  def order_by_appearances(cast) do
    Enum.sort_by(cast, fn person ->
      {-(person.total_episode_count || 0), person.order || @unbilled_order}
    end)
  end

  @doc """
  Splits `cast` against an episode's membership set of TMDB person ids:
  `{members, rest}`, each appearance-ordered. Entries without a
  `tmdb_person_id` can never match and land in `rest`.
  """
  @spec partition_by_membership([map()], [integer()]) :: {[map()], [map()]}
  def partition_by_membership(cast, member_ids) do
    member_set = MapSet.new(member_ids)

    {members, rest} =
      Enum.split_with(cast, fn person ->
        is_integer(person.tmdb_person_id) and MapSet.member?(member_set, person.tmdb_person_id)
      end)

    {order_by_appearances(members), order_by_appearances(rest)}
  end

  @doc """
  The cast members to render for `query`, capped at `limit`, preserving
  the input order (callers sort first).

  An empty or nil query selects the first `limit` entries. Otherwise,
  entries whose name or character contains `query` (case-insensitive,
  matched literally) are selected, up to `limit`.
  """
  @spec visible_cast([map()], String.t() | nil, non_neg_integer()) :: [map()]
  def visible_cast(cast, query, limit), do: Enum.take(matching_cast(cast, query), limit)

  @doc """
  How many cast members match `query` — the whole cast for an empty
  query. With `visible_cast/3` this yields the *Show more* remainder.
  """
  @spec match_count([map()], String.t() | nil) :: non_neg_integer()
  def match_count(cast, query), do: length(matching_cast(cast, query))

  @doc "Whether `query` is an active filter (non-blank)."
  @spec filtering?(String.t() | nil) :: boolean()
  def filtering?(query), do: String.trim(query || "") != ""

  @doc """
  Whether `cast` warrants a filter input — more than one page of cards.
  Shared by `CastPanel` and `DetailPanel`, which host the same filter
  form in different places.
  """
  @spec show_filter?([map()]) :: boolean()
  def show_filter?(cast), do: length(cast) > @page_size

  defp matching_cast(cast, query) do
    case String.trim(query || "") do
      "" -> cast
      trimmed -> Enum.filter(cast, &matches?(&1, String.downcase(trimmed)))
    end
  end

  defp matches?(person, query) do
    String.contains?(searchable(person.name), query) or
      String.contains?(searchable(person.character), query)
  end

  defp searchable(value) when is_binary(value), do: String.downcase(value)
  defp searchable(_value), do: ""
end
