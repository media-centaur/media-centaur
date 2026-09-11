defmodule MediaCentaur.TMDB.TitleIdentity do
  @moduledoc """
  Which film or show a thing is — the eight fields that answer that
  question, carried as one value.

  Identity is distinct from two neighbours it used to travel beside as
  loose fields:

    * **scope** — which episode, season or collection part *within* a
      title. An id names the title, never the scope, so a `tvdb_id`
      match still leaves season and episode to be checked.
    * **bounds** — how good a copy is acceptable. `Acquisition`'s
      `plan.criteria`.

  ## Why this is a value and not eight columns copied by hand

  These fields used to be spelled out field-by-field at every hop from a
  TMDB payload to the matcher — seven plan doors and ten projections, each
  one an opportunity to omit one. One door did: the unattended movie
  drop planner built its plan from the title alone, so a different film
  sharing the ASCII-folded name passed the matcher and was grabbed once a
  day until someone noticed. Passing one value makes that shape of
  mistake unavailable: there is no per-field assembly to leave a field
  out of.

  `@enforce_keys` covers what TMDB always supplies. `imdb_id`, `tvdb_id`,
  `original_title` and `year` are genuinely optional — TMDB does not hold
  every id for every title, and a missing one degrades the match to the
  name heuristic rather than failing it.

  ## Comparing two identities

  `compare/2` is the one identity comparison in the system. It answers
  `:match` / `:mismatch` / `:unknown` from external ids alone — the exact
  question, as against parsing a release name, which is a heuristic.
  `Search.TitleMatcher` consumes it for indexer results; the import path
  consumes it to notice that a landing file is not the film its grab
  asked for.

  One id agreeing outweighs another disagreeing: indexers mis-tag a
  single field far more often than they get every field wrong.

  ## Homed in TMDB

  Identity originates here and `TMDB.Identifiers` already owns where the
  ids live in a payload. Every context that needs to name this type
  (`Acquisition`, `ReleaseTracking`, `Pipeline`) already declares TMDB as
  a `Boundary` dep, so it costs no new edge. It deliberately does **not**
  get embedded in `Search.Criteria` — that would make `Search` depend on
  TMDB and reverse the inversion that context keeps on purpose. The
  projection into `Criteria` lives in `Acquisition`, which deps both.
  """

  @enforce_keys [:tmdb_type, :tmdb_id, :title]
  defstruct [
    :tmdb_type,
    :tmdb_id,
    :title,
    :imdb_id,
    :tvdb_id,
    :original_title,
    :year,
    origin_country: []
  ]

  @type tmdb_type :: :movie | :tv

  @type t :: %__MODULE__{
          tmdb_type: tmdb_type(),
          tmdb_id: String.t(),
          title: String.t(),
          imdb_id: String.t() | nil,
          tvdb_id: String.t() | nil,
          original_title: String.t() | nil,
          year: integer() | nil,
          origin_country: [String.t()]
        }

  alias MediaCentaur.TMDB.{Identifiers, Mapper}

  @doc """
  Builds an identity, normalising the fields that have more than one
  spelling in the wild. `tmdb_id` is always a string; `tmdb_type`
  accepts the library's `:tv_series` vocabulary alongside `:tv`.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      tmdb_type: normalize_type(fetch(attrs, :tmdb_type)),
      tmdb_id: presence(fetch(attrs, :tmdb_id)),
      title: fetch(attrs, :title),
      imdb_id: fetch(attrs, :imdb_id),
      tvdb_id: fetch(attrs, :tvdb_id),
      original_title: fetch(attrs, :original_title),
      year: fetch(attrs, :year),
      origin_country: fetch(attrs, :origin_country) || []
    }
  end

  @doc """
  The identity carried by a TMDB detail payload — the one constructor
  that reads TMDB's own shape, so no caller has to know that a movie
  keeps `imdb_id` at the top level and a series keeps it under
  `external_ids`.
  """
  @spec from_payload(:movie | :tv | :tv_series, map()) :: t()
  def from_payload(type, payload) when is_map(payload) do
    type = normalize_type(type)
    ids = Identifiers.from_payload(type, payload)

    new(%{
      tmdb_type: type,
      tmdb_id: payload["id"],
      title: payload["title"] || payload["name"],
      imdb_id: ids.imdb_id,
      tvdb_id: ids.tvdb_id,
      original_title: Mapper.original_title(payload),
      year: payload_year(type, payload),
      origin_country: payload["origin_country"] || []
    })
  end

  @doc """
  Layers a fuller identity of the same film over a partial one.

  The caller that asked TMDB for a title already knows its id and the
  name it searched under; the payload that comes back knows the external
  ids, the original title and the release year. `overlay` wins wherever
  it holds a value, `base` supplies the rest — so a payload missing a
  field never blanks one the caller already had.
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = base, %__MODULE__{} = overlay) do
    %{
      base
      | tmdb_type: overlay.tmdb_type || base.tmdb_type,
        tmdb_id: overlay.tmdb_id || base.tmdb_id,
        title: overlay.title || base.title,
        imdb_id: overlay.imdb_id || base.imdb_id,
        tvdb_id: overlay.tvdb_id || base.tvdb_id,
        original_title: overlay.original_title || base.original_title,
        year: overlay.year || base.year,
        origin_country: presence_list(overlay.origin_country) || base.origin_country
    }
  end

  @doc """
  Compares a wanted identity against whatever ids something declares.

    * `:match` — at least one id pair agrees. Identity is settled, so a
      caller may skip the name and year heuristics entirely.
    * `:mismatch` — ids were comparable and none agreed. A rejection
      name parsing can never assert.
    * `:unknown` — nothing comparable. The caller's heuristics decide,
      unchanged.

  The right-hand side is **any** map carrying `imdb_id` / `tmdb_id` /
  `tvdb_id` — an indexer's `Search.SearchResult`, a parsed file, or
  another `TitleIdentity`. It is deliberately not required to be a full
  identity: a declared side routinely carries one id and nothing else,
  and `@enforce_keys` here exists to stop *our* doors building a
  half-identity, not to reject an indexer's sparse claim.
  """
  @spec compare(t() | nil, t() | map() | nil) :: :match | :mismatch | :unknown
  def compare(%__MODULE__{} = wanted, declared) when is_map(declared) do
    [:imdb_id, :tmdb_id, :tvdb_id]
    |> Enum.map(&compare_field(Map.get(wanted, &1), declared_id(declared, &1)))
    |> resolve()
  end

  def compare(_wanted, _declared), do: :unknown

  # A declared side may spell ids as integers (Prowlarr) or omit them.
  defp declared_id(declared, key) do
    case Map.get(declared, key, Map.get(declared, to_string(key))) do
      nil -> nil
      id when is_integer(id) and id > 0 -> Integer.to_string(id)
      id when is_binary(id) -> if String.trim(id) != "", do: id
      _other -> nil
    end
  end

  defp compare_field(nil, _right), do: :unknown
  defp compare_field(_left, nil), do: :unknown
  defp compare_field(same, same), do: :match
  defp compare_field(_left, _right), do: :mismatch

  # One id agreeing outweighs another disagreeing.
  defp resolve(verdicts) do
    cond do
      :match in verdicts -> :match
      :mismatch in verdicts -> :mismatch
      true -> :unknown
    end
  end

  defp payload_year(:movie, payload), do: year_of(payload["release_date"])
  defp payload_year(:tv, payload), do: year_of(payload["first_air_date"])

  defp year_of(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, %Date{year: year}} -> year
      {:error, _reason} -> nil
    end
  end

  defp year_of(_date), do: nil

  defp normalize_type(:tv_series), do: :tv
  defp normalize_type("tv_series"), do: :tv
  defp normalize_type("movie"), do: :movie
  defp normalize_type("tv"), do: :tv
  defp normalize_type(type) when type in [:movie, :tv], do: type

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp presence(nil), do: nil
  defp presence(value) when is_integer(value), do: Integer.to_string(value)

  defp presence(value) when is_binary(value) do
    if String.trim(value) != "", do: value
  end

  defp presence(value), do: to_string(value)

  defp presence_list([]), do: nil
  defp presence_list(list), do: list
end
