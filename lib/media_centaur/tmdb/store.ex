defmodule MediaCentaur.TMDB.Store do
  @moduledoc """
  The app's knowledge of a TMDB title, one record per identity: TMDB's
  last answer, when it was learned, and when the app is next due to ask
  (`MediaCentaur.TMDB.Store.TitleRecord`, with one
  `MediaCentaur.TMDB.Store.SeasonRecord` per stored season). Everything
  the app shows or schedules about a title is a projection of this
  record; nothing else fetches (campaign `tmdb-fetch-policy`; ADR-071).

  This module is the only writer. Three ways a record changes:

    * **First contact** — `ensure/2` and `ensure_season/3` fetch a title
      the app has never held. Never a request when the title is stored.
    * **A check** — `check/2` revalidates a stored title with its own
      ETag through `MediaCentaur.TMDB.Client.detail/2`; a 304 moves the
      fetch time and re-derives the schedule (today moved), a 200
      replaces the payload. Open seasons are checked with the title. A
      change is published as `{:tmdb_title_changed, {tmdb_id, media_type}}`
      on `MediaCentaur.Topics.tmdb_titles/0`.
    * **Write-through** — `record_fetched/3` and `record_season_fetched/4`
      are also called by `TMDB.Client` for every detail payload a caller
      fetches, so the store fills while callers still fetch for
      themselves. Transitional: removed when the last detail caller
      reads through this module.

  The schedule columns are derived on every write by
  `MediaCentaur.TMDB.Schedule`, so `due/1` is a plain query. Ids arrive
  as integers or numeric strings — the client's callers pass both.
  """

  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.{Mapper, Schedule}
  alias MediaCentaur.TMDB.Store.{SeasonRecord, TitleRecord}

  @type media_type :: :movie | :tv_series
  @type ref :: {pos_integer() | String.t(), media_type()}

  # --- Reads ---

  @doc "The stored title, or nil."
  @spec get(ref()) :: TitleRecord.t() | nil
  def get({tmdb_id, media_type}) do
    Repo.get_by(TitleRecord, tmdb_id: normalize_id(tmdb_id), media_type: media_type)
  end

  @doc "The stored season, or nil."
  @spec get_season(pos_integer() | String.t(), pos_integer()) :: SeasonRecord.t() | nil
  def get_season(tmdb_id, season_number) do
    Repo.get_by(SeasonRecord, tmdb_id: normalize_id(tmdb_id), season_number: season_number)
  end

  @doc "Every stored season of a series, by season number."
  @spec seasons(pos_integer() | String.t()) :: [SeasonRecord.t()]
  def seasons(tmdb_id) do
    tmdb_id = normalize_id(tmdb_id)
    Repo.all(from s in SeasonRecord, where: s.tmdb_id == ^tmdb_id, order_by: s.season_number)
  end

  @doc "Unsettled titles whose check time has passed, oldest due first."
  @spec due(DateTime.t()) :: [TitleRecord.t()]
  def due(%DateTime{} = now) do
    Repo.all(
      from t in TitleRecord,
        where: not is_nil(t.next_check_at) and t.next_check_at <= ^now,
        order_by: t.next_check_at
    )
  end

  # --- Writes ---

  @doc """
  Records a title's detail payload as fetched now. An identical payload
  moves only `fetched_at`; a different one replaces it and moves
  `changed_at`. A nil `etag` keeps the stored one (a body served by the
  response cache carries none). The schedule is re-derived either way.
  """
  @spec record_fetched(ref(), map(), String.t() | nil) ::
          {:ok, TitleRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_fetched({tmdb_id, media_type}, payload, etag) when is_map(payload) do
    tmdb_id = normalize_id(tmdb_id)
    now = now()
    payload = trim_payload(payload)
    existing = get({tmdb_id, media_type})

    attrs =
      existing
      |> fetched_attrs(payload, etag, now)
      |> Map.merge(schedule_attrs(existing, media_type, payload, seasons(tmdb_id), now))

    (existing || %TitleRecord{tmdb_id: tmdb_id, media_type: media_type})
    |> TitleRecord.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Records a season's payload as fetched now, then re-derives its
  series' schedule, since the season's episode dates are part of it.
  """
  @spec record_season_fetched(pos_integer() | String.t(), pos_integer(), map(), String.t() | nil) ::
          {:ok, SeasonRecord.t()} | {:error, Ecto.Changeset.t()}
  def record_season_fetched(tmdb_id, season_number, payload, etag) when is_map(payload) do
    tmdb_id = normalize_id(tmdb_id)
    now = now()
    existing = get_season(tmdb_id, season_number)

    result =
      (existing || %SeasonRecord{tmdb_id: tmdb_id, season_number: season_number})
      |> SeasonRecord.changeset(fetched_attrs(existing, payload, etag, now))
      |> Repo.insert_or_update()

    with {:ok, _season} <- result do
      reschedule_series(tmdb_id)
      result
    end
  end

  @doc """
  The payload as the store keeps it: as received, except the `images`
  block, which is reduced to the one logo `Mapper.pick_logo_path/1`
  selects. Posters and backdrops are already named at the top level;
  the rest of the block is the bulk of a detail response and nothing
  reads it.
  """
  @spec trim_payload(map()) :: map()
  def trim_payload(%{"images" => _images} = payload) do
    logo_path = Mapper.pick_logo_path(payload)
    logos = get_in(payload, ["images", "logos"]) || []
    Map.put(payload, "images", %{"logos" => Enum.filter(logos, &(&1["file_path"] == logo_path))})
  end

  def trim_payload(payload), do: payload

  # --- Internals ---

  defp fetched_attrs(nil, payload, etag, now) do
    %{payload: payload, etag: etag, fetched_at: now, changed_at: now}
  end

  defp fetched_attrs(%{payload: stored, etag: stored_etag}, payload, etag, now) do
    base = %{payload: payload, etag: etag || stored_etag, fetched_at: now}
    if payload == stored, do: base, else: Map.put(base, :changed_at, now)
  end

  defp schedule_attrs(existing, media_type, payload, season_records, fetched_at) do
    season_payloads = Enum.map(season_records, & &1.payload)
    today = DateTime.to_date(fetched_at)
    plan = Schedule.plan(media_type, payload, season_payloads, today, fetched_at)

    %{
      next_event_on: plan.next_event_on,
      next_check_at: plan.next_check_at,
      settled_at: settled_at(existing, plan, fetched_at)
    }
  end

  defp settled_at(_existing, %{settled?: false}, _now), do: nil
  defp settled_at(%TitleRecord{settled_at: %DateTime{} = at}, %{settled?: true}, _now), do: at
  defp settled_at(_existing, %{settled?: true}, now), do: now

  # A season write does not mean the series was asked, so the schedule
  # is re-derived from the series' own fetch time.
  defp reschedule_series(tmdb_id) do
    case get({tmdb_id, :tv_series}) do
      nil ->
        :ok

      %TitleRecord{} = record ->
        attrs =
          schedule_attrs(record, :tv_series, record.payload, seasons(tmdb_id), record.fetched_at)

        {:ok, _record} = record |> TitleRecord.changeset(attrs) |> Repo.update()
        :ok
    end
  end

  defp now, do: DateTime.utc_now(:second)

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
end
