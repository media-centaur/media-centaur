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

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.{Client, Mapper, Schedule}
  alias MediaCentaur.TMDB.Store.{SeasonRecord, TitleRecord}
  alias MediaCentaur.Topics

  @type media_type :: :movie | :tv_series
  @type ref :: {pos_integer() | String.t(), media_type()}

  # --- Reads ---

  @doc "The stored title, or nil (also for an id that is not a TMDB id)."
  @spec get(ref()) :: TitleRecord.t() | nil
  def get({tmdb_id, media_type}) do
    case parse_id(tmdb_id) do
      {:ok, id} -> Repo.get_by(TitleRecord, tmdb_id: id, media_type: media_type)
      :error -> nil
    end
  end

  @doc "The stored season, or nil."
  @spec get_season(pos_integer() | String.t(), pos_integer()) :: SeasonRecord.t() | nil
  def get_season(tmdb_id, season_number) do
    case parse_id(tmdb_id) do
      {:ok, id} -> Repo.get_by(SeasonRecord, tmdb_id: id, season_number: season_number)
      :error -> nil
    end
  end

  @doc "Every stored season of a series, by season number."
  @spec seasons(pos_integer() | String.t()) :: [SeasonRecord.t()]
  def seasons(tmdb_id) do
    case parse_id(tmdb_id) do
      {:ok, id} ->
        Repo.all(from s in SeasonRecord, where: s.tmdb_id == ^id, order_by: s.season_number)

      :error ->
        []
    end
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
          {:ok, TitleRecord.t()} | {:error, Ecto.Changeset.t() | :invalid_id}
  def record_fetched({tmdb_id, media_type}, payload, etag) when is_map(payload) do
    with {:ok, id} <- parse_id(tmdb_id),
         {:ok, record, _changed?} <- store_title({id, media_type}, payload, etag) do
      {:ok, record}
    else
      :error -> {:error, :invalid_id}
      {:error, _changeset} = error -> error
    end
  end

  @doc """
  Records a season's payload as fetched now, then re-derives its
  series' schedule, since the season's episode dates are part of it.
  """
  @spec record_season_fetched(pos_integer() | String.t(), pos_integer(), map(), String.t() | nil) ::
          {:ok, SeasonRecord.t()} | {:error, Ecto.Changeset.t() | :invalid_id}
  def record_season_fetched(tmdb_id, season_number, payload, etag) when is_map(payload) do
    with {:ok, id} <- parse_id(tmdb_id),
         {:ok, season, _changed?} <- store_season(id, season_number, payload, etag) do
      {:ok, season}
    else
      :error -> {:error, :invalid_id}
      {:error, _changeset} = error -> error
    end
  end

  @doc """
  The payload as the store keeps it — what the app re-reads, not
  everything TMDB sends. Two blocks go: `images` is reduced to the one
  logo `Mapper.pick_logo_path/1` selects (posters and backdrops are
  named at the top level), and the credits — a title's `credits` or
  `aggregate_credits`, a season's `credits`, an episode's `guest_stars`
  and `crew` — are dropped outright. Credits are read once, at import,
  to project cast onto a library entity; the import requests them then.
  Measured before the decision: they were nine tenths of a 245 KB series
  and a 485 KB season.
  """
  @spec trim_payload(map()) :: map()
  def trim_payload(payload) when is_map(payload) do
    payload
    |> trim_images()
    |> Map.drop(["credits", "aggregate_credits"])
    |> trim_episodes()
  end

  defp trim_images(%{"images" => _images} = payload) do
    logo_path = Mapper.pick_logo_path(payload)
    logos = get_in(payload, ["images", "logos"]) || []
    Map.put(payload, "images", %{"logos" => Enum.filter(logos, &(&1["file_path"] == logo_path))})
  end

  defp trim_images(payload), do: payload

  defp trim_episodes(%{"episodes" => episodes} = payload) when is_list(episodes) do
    Map.put(payload, "episodes", Enum.map(episodes, &Map.drop(&1, ["guest_stars", "crew"])))
  end

  defp trim_episodes(payload), do: payload

  # --- First contact and checks ---

  @doc "The stored title, fetched on first contact when the app has never held it."
  @spec ensure(ref(), keyword()) :: {:ok, TitleRecord.t()} | {:error, any()}
  def ensure(ref, opts \\ []) do
    case get(ref) do
      nil -> first_contact(ref, opts)
      %TitleRecord{} = record -> {:ok, record}
    end
  end

  @doc "The stored season, fetched on first contact when the app has never held it."
  @spec ensure_season(pos_integer() | String.t(), pos_integer(), keyword()) ::
          {:ok, SeasonRecord.t()} | {:error, any()}
  def ensure_season(tmdb_id, season_number, opts \\ []) do
    case get_season(tmdb_id, season_number) do
      nil -> first_contact_season(tmdb_id, season_number, opts)
      %SeasonRecord{} = record -> {:ok, record}
    end
  end

  @doc """
  Revalidates a stored title with its ETag, and its open seasons with
  theirs. `{:ok, :unchanged, record}` when TMDB answered 304 for all of
  them; `{:ok, :changed, record}` when any payload was replaced, after
  publishing `{:tmdb_title_changed, ref}`. A title the store does not
  hold is first contact, reported as changed. Any TMDB failure is
  returned and leaves the records as they were.
  """
  @spec check(ref(), keyword()) ::
          {:ok, :unchanged | :changed, TitleRecord.t()} | {:error, any()}
  def check(ref, opts \\ []) do
    case get(ref) do
      nil ->
        with {:ok, record} <- first_contact(ref, opts) do
          publish_changed(record)
          {:ok, :changed, record}
        end

      %TitleRecord{} = record ->
        with {:ok, title_changed?} <- revalidate_title(record, opts),
             {:ok, seasons_changed?} <- revalidate_open_seasons(record, opts) do
          record = get(ref)

          if title_changed? or seasons_changed? do
            publish_changed(record)
            {:ok, :changed, record}
          else
            {:ok, :unchanged, record}
          end
        end
    end
  end

  defp first_contact({tmdb_id, media_type} = ref, opts) do
    with {:ok, %{body: body, etag: etag}} <- Client.detail(ref, opts),
         {:ok, record} <- record_fetched(ref, body, etag) do
      Log.info(
        :tmdb,
        "stored #{subject(media_type, tmdb_id)} — first contact#{schedule_words(record)}"
      )

      {:ok, record}
    end
  end

  defp first_contact_season(tmdb_id, season_number, opts) do
    with {:ok, %{body: body, etag: etag}} <-
           Client.detail({:season, tmdb_id, season_number}, opts) do
      record_season_fetched(tmdb_id, season_number, body, etag)
    end
  end

  # {:ok, changed?} | {:error, reason}
  defp revalidate_title(%TitleRecord{} = record, opts) do
    ref = {record.tmdb_id, record.media_type}
    subject = subject(record.media_type, record.tmdb_id)

    case Client.detail(ref, Keyword.put(opts, :if_none_match, record.etag)) do
      {:ok, :unchanged} ->
        {:ok, touched} = touch_title(record)
        Log.info(:tmdb, "checked #{subject} — unchanged#{schedule_words(touched)}")
        {:ok, false}

      {:ok, %{body: body, etag: etag}} ->
        {:ok, replaced, changed?} = store_title(ref, body, etag)
        outcome = if changed?, do: "changed", else: "unchanged"
        Log.info(:tmdb, "checked #{subject} — #{outcome}#{schedule_words(replaced)}")
        {:ok, changed?}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp revalidate_open_seasons(%TitleRecord{media_type: :movie}, _opts), do: {:ok, false}

  defp revalidate_open_seasons(%TitleRecord{media_type: :tv_series} = record, opts) do
    title = get({record.tmdb_id, :tv_series})
    today = Date.utc_today()

    record.tmdb_id
    |> seasons()
    |> Enum.filter(&Schedule.open_season?(&1.payload, title.payload, today))
    |> Enum.reduce_while({:ok, false}, fn season, {:ok, any_changed?} ->
      case revalidate_season(season, opts) do
        {:ok, changed?} -> {:cont, {:ok, any_changed? or changed?}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revalidate_season(%SeasonRecord{} = season, opts) do
    ref = {:season, season.tmdb_id, season.season_number}

    case Client.detail(ref, Keyword.put(opts, :if_none_match, season.etag)) do
      {:ok, :unchanged} ->
        {:ok, _touched} = season |> SeasonRecord.changeset(%{fetched_at: now()}) |> Repo.update()
        {:ok, false}

      {:ok, %{body: body, etag: etag}} ->
        {:ok, _replaced, changed?} =
          store_season(season.tmdb_id, season.season_number, body, etag)

        {:ok, changed?}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A 304: TMDB answered, nothing changed. The fetch time moves and the
  # schedule is re-derived, because today moved.
  defp touch_title(%TitleRecord{} = record) do
    now = now()

    attrs =
      record
      |> schedule_attrs(record.media_type, record.payload, seasons(record.tmdb_id), now)
      |> Map.put(:fetched_at, now)

    record |> TitleRecord.changeset(attrs) |> Repo.update()
  end

  defp publish_changed(%TitleRecord{tmdb_id: tmdb_id, media_type: media_type}) do
    Topics.publish(Topics.tmdb_titles(), {:tmdb_title_changed, {tmdb_id, media_type}})
  end

  defp subject(:movie, tmdb_id), do: "movie tmdb:#{tmdb_id}"
  defp subject(:tv_series, tmdb_id), do: "TV tmdb:#{tmdb_id}"

  defp schedule_words(%TitleRecord{settled_at: %DateTime{}}), do: ", settled"

  defp schedule_words(%TitleRecord{next_check_at: %DateTime{} = at}),
    do: ", next check #{DateTime.to_date(at)}"

  defp schedule_words(_record), do: ""

  # --- Internals ---

  # The write paths behind the public record_* functions and the checks.
  # Both return {:ok, record, changed?} — whether the payload differs
  # from what was stored, decided by comparing payloads, never by
  # comparing timestamps (two writes in one second read as one instant).
  # Ids are already parsed.
  #
  # Read-then-write, so two processes fetching the same new title can
  # both read "no row" and both insert. The loser's unique violation is
  # retried once as the update it should have been; the payload is the
  # same fetch either way.
  defp store_title(ref, payload, etag) do
    write_title(ref, trim_payload(payload), etag, :first_try)
  end

  defp store_season(tmdb_id, season_number, payload, etag) do
    with {:ok, season, changed?} <-
           write_season(tmdb_id, season_number, trim_payload(payload), etag, :first_try) do
      reschedule_series(tmdb_id)
      {:ok, season, changed?}
    end
  end

  defp write_title({tmdb_id, media_type} = ref, payload, etag, attempt) do
    now = now()
    existing = get(ref)
    changed? = existing == nil or payload != existing.payload

    attrs =
      existing
      |> fetched_attrs(payload, etag, now)
      |> Map.merge(schedule_attrs(existing, media_type, payload, seasons(tmdb_id), now))

    result =
      (existing || %TitleRecord{tmdb_id: tmdb_id, media_type: media_type})
      |> TitleRecord.changeset(attrs)
      |> Repo.insert_or_update()

    case result do
      {:ok, record} ->
        {:ok, record, changed?}

      {:error, %Ecto.Changeset{} = changeset} when attempt == :first_try ->
        if unique_violation?(changeset),
          do: write_title(ref, payload, etag, :retry),
          else: {:error, changeset}

      {:error, _changeset} = error ->
        error
    end
  end

  defp write_season(tmdb_id, season_number, payload, etag, attempt) do
    existing = get_season(tmdb_id, season_number)
    changed? = existing == nil or payload != existing.payload

    result =
      (existing || %SeasonRecord{tmdb_id: tmdb_id, season_number: season_number})
      |> SeasonRecord.changeset(fetched_attrs(existing, payload, etag, now()))
      |> Repo.insert_or_update()

    case result do
      {:ok, season} ->
        {:ok, season, changed?}

      {:error, %Ecto.Changeset{} = changeset} when attempt == :first_try ->
        if unique_violation?(changeset),
          do: write_season(tmdb_id, season_number, payload, etag, :retry),
          else: {:error, changeset}

      {:error, _changeset} = error ->
        error
    end
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end

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

  # A TMDB id is a positive integer; callers pass it as an integer or as
  # its decimal spelling. Anything else is refused rather than stored.
  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> {:ok, int}
      _other -> :error
    end
  end

  defp parse_id(_id), do: :error
end
