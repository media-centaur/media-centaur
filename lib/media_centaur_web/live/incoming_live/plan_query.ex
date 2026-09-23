defmodule MediaCentaurWeb.IncomingLive.PlanQuery do
  @moduledoc """
  The plan modal's address — the `?plan=…` query Incoming reads to open
  the board or the picker (UIDR-014) — built and parsed in one place, so
  every link, patch and navigate to it agrees on the params (spec
  2026-09-23, coherence pass 2).

  Two shapes. The board of an existing plan: `plan=<id>`. The picker for
  a series, or the confirm card for a movie:
  `plan=new&tmdb_id=<id>&tmdb_type=tv|movie`, optionally `&mode=<mode>`
  — a planning mode's wire form (`PlanningMode.parse_mode/1`) naming
  which mode the picker's Download performs. Absent means the person's
  default; Incoming resolves that, this module only carries it. A `mode`
  or `tmdb_type` the app cannot mean parses as `{:error, :malformed}`.

  Builders return query maps: a host on Incoming patches with one
  (`incoming_path/2`), any other page navigates to `path/1`.
  """

  use MediaCentaurWeb, :verified_routes

  alias MediaCentaur.Settings.Preferences.PlanningMode

  @tmdb_types ["tv", "movie"]

  @type query :: %{String.t() => String.t()}
  @type parsed ::
          :closed
          | {:board, plan_id :: String.t()}
          | {:picker, tmdb_id :: String.t(), tmdb_type :: String.t(), PlanningMode.mode() | nil}
          | {:error, :malformed}

  @doc "The board of an existing plan."
  @spec board(String.t()) :: query()
  def board(plan_id) when is_binary(plan_id), do: %{"plan" => plan_id}

  @doc """
  The picker for a series (`"tv"`) or the confirm card for a movie
  (`"movie"`). `mode` is the planning mode the picker's Download performs,
  or nil for the person's default.
  """
  @spec picker(String.t() | integer(), String.t(), PlanningMode.mode() | nil) :: query()
  def picker(tmdb_id, tmdb_type, mode \\ nil) when tmdb_type in @tmdb_types do
    query = %{"plan" => "new", "tmdb_id" => to_string(tmdb_id), "tmdb_type" => tmdb_type}
    if mode, do: Map.put(query, "mode", Atom.to_string(mode)), else: query
  end

  @doc "A query as a path to Incoming, for a navigate from another page."
  @spec path(query()) :: String.t()
  def path(query) when is_map(query), do: ~p"/incoming?#{query}"

  @doc "What Incoming's params say the plan modal should show."
  @spec parse(map()) :: parsed()
  def parse(%{"plan" => "new"} = params), do: parse_picker(params)
  def parse(%{"plan" => plan_id}) when is_binary(plan_id), do: {:board, plan_id}
  def parse(%{"plan" => _not_a_string}), do: {:error, :malformed}
  def parse(_params), do: :closed

  defp parse_picker(%{"tmdb_id" => tmdb_id, "tmdb_type" => tmdb_type} = params)
       when is_binary(tmdb_id) and tmdb_type in @tmdb_types do
    case Map.fetch(params, "mode") do
      :error -> {:picker, tmdb_id, tmdb_type, nil}
      {:ok, mode} -> parse_mode(tmdb_id, tmdb_type, mode)
    end
  end

  defp parse_picker(_params), do: {:error, :malformed}

  defp parse_mode(tmdb_id, tmdb_type, mode) do
    case PlanningMode.parse_mode(mode) do
      {:ok, mode} -> {:picker, tmdb_id, tmdb_type, mode}
      :error -> {:error, :malformed}
    end
  end
end
