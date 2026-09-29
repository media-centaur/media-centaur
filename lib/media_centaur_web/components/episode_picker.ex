defmodule MediaCentaurWeb.Components.EpisodePicker do
  @moduledoc """
  The reviewer's choice of which episode a file is, for a file matched to a
  series whose name does not number the episode (a yearly special named for
  its year, a single-file release). A native select over the series'
  episodes, one group per season, as the Review page's search form draws its
  type select.

  `seasons` is `MediaCentaur.Review.episode_choices/1`'s shape; `nil` while
  it loads. `selected` is the file's current `{season, episode}` — offered
  in advance by `MediaCentaur.Review.EpisodeChoice.preselect/2` when the
  file's year identifies one episode. A change pushes `event` with
  `%{"file_id" => ..., "episode" => "season:episode"}`.
  """
  use MediaCentaurWeb, :html

  attr :id, :string, required: true
  attr :file_id, :string, required: true, doc: "the review item the choice is for"

  attr :seasons, :list,
    default: nil,
    doc: "`[%{season_number, name, episodes: [%{episode_number, name, air_date}]}]`; nil while loading"

  attr :selected, :any, default: nil, doc: "`{season_number, episode_number}` or nil"
  attr :event, :string, default: "choose_episode"

  def episode_picker(assigns) do
    ~H"""
    <form id={@id} phx-change={@event} class="form-control">
      <input type="hidden" name="file_id" value={@file_id} />
      <label class="label py-0" for={"#{@id}-select"}>
        <span class="label-text text-xs">Episode</span>
      </label>
      <p :if={is_nil(@seasons)} class="text-sm text-base-content/55">Loading episodes…</p>
      <p :if={@seasons == []} class="text-sm text-error">
        TMDB lists no episodes for this series. Match the file to a movie instead.
      </p>
      <select
        :if={@seasons not in [nil, []]}
        id={"#{@id}-select"}
        name="episode"
        class="select select-bordered select-sm w-full"
      >
        <option value="" disabled selected={is_nil(@selected)}>Choose the episode</option>
        <optgroup
          :for={season <- @seasons}
          label={season.name || "Season #{season.season_number}"}
        >
          <option
            :for={episode <- season.episodes}
            value={"#{season.season_number}:#{episode.episode_number}"}
            selected={@selected == {season.season_number, episode.episode_number}}
          >
            {episode_label(season.season_number, episode)}
          </option>
        </optgroup>
      </select>
    </form>
    """
  end

  defp episode_label(season_number, episode) do
    code = "S#{pad(season_number)}E#{pad(episode.episode_number)}"
    name = if episode.name, do: " · #{episode.name}", else: ""
    aired = if episode.air_date, do: " (#{String.slice(episode.air_date, 0, 4)})", else: ""
    code <> name <> aired
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
