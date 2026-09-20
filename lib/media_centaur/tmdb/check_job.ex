defmodule MediaCentaur.TMDB.CheckJob do
  @moduledoc """
  The tick that asks TMDB only what is due (ADR-071 §3). Every quarter
  hour, and once at boot: the referenced titles the store does not hold
  yet are first-contacted, bounded per tick so a fresh install fills in
  over a few ticks rather than one burst; then every stored title that
  is due and scheduled (`MediaCentaur.TMDB.References.scheduled/0`) is
  checked — one conditional request, a 304 when nothing changed.

  Held like every metered job: when TMDB is unavailable the tick does
  nothing and the next one tries again. Nothing is lost, because
  due-ness is a stored fact. A title whose request fails is logged and
  skipped; the tick goes on. Between titles the tick re-reads `up?/1`,
  so an outage that begins mid-tick stops the spending at once.
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.{References, Store}

  @first_contacts_per_tick 50

  @doc "How many titles the store lacks are first-contacted in one tick."
  @spec first_contacts_per_tick() :: pos_integer()
  def first_contacts_per_tick, do: @first_contacts_per_tick

  @impl Oban.Worker
  def perform(_job) do
    if IntegrationAvailability.available?(:tmdb) do
      tick()
    else
      Log.debug(:tmdb, "check tick held — TMDB is unavailable")
    end

    :ok
  end

  defp tick do
    scheduled = References.scheduled()
    stored = Store.get_many(scheduled)

    contacted =
      scheduled
      |> Enum.reject(&Map.has_key?(stored, &1))
      |> Enum.take(@first_contacts_per_tick)
      |> Enum.map(fn ref -> while_up(fn -> Store.ensure(ref) end) end)
      |> Enum.count(&match?({:ok, _record}, &1))

    outcomes =
      DateTime.utc_now()
      |> Store.due()
      |> Enum.map(&{&1.tmdb_id, &1.media_type})
      |> Enum.filter(&MapSet.member?(scheduled, &1))
      |> Enum.map(fn ref -> while_up(fn -> Store.check(ref) end) end)

    checked = Enum.count(outcomes, &match?({:ok, _outcome, _record}, &1))
    changed = Enum.count(outcomes, &match?({:ok, :changed, _record}, &1))

    if contacted + checked > 0 do
      Log.info(
        :tmdb,
        "check tick — #{contacted} first contacts, #{checked} checks, #{changed} changed"
      )
    end
  end

  # Spend a request only while TMDB is still up; a failure is the
  # title's, not the tick's.
  defp while_up(request) do
    if IntegrationAvailability.up?(:tmdb) do
      case request.() do
        {:error, reason} ->
          Log.info(:tmdb, "check skipped a title — #{inspect(reason)}")
          :skipped

        answered ->
          answered
      end
    else
      :held
    end
  end
end
