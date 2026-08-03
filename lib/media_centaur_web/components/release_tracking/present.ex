defmodule MediaCentaurWeb.Components.ReleaseTracking.Present do
  @moduledoc """
  Pure presentation helpers for the Upcoming rail — status labels/tones/icons,
  the "what drops" descriptor, relative-day copy, and bucket labels.

  Extracted from the components per ADR-030 so the wording and the status →
  colour mapping are unit-testable without rendering. Colour is reserved for
  status: `:success` (armed / landed), `:info` (under pursuit), `:muted`
  (info-only theatrical), `:neutral` (plain upcoming / unscheduled).
  """

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event

  @type tone :: :success | :info | :muted | :neutral

  @spec status_label(atom()) :: String.t()
  def status_label(:armed), do: "Will grab"
  def status_label(:armed_fallback), do: "Grabs if still missing"
  def status_label(:under_pursuit), do: "Grabbing"
  def status_label(:in_library), do: "In your library"
  def status_label(:theatrical_info), do: "In theaters"
  def status_label(:upcoming), do: "Upcoming"
  def status_label(:unscheduled), do: "Not scheduled"

  @spec status_tone(atom()) :: tone()
  def status_tone(:armed), do: :success
  def status_tone(:in_library), do: :success
  def status_tone(:under_pursuit), do: :info
  def status_tone(:theatrical_info), do: :muted
  # A fallback date carries no promise of its own — neutral, not success.
  def status_tone(status) when status in [:armed_fallback, :upcoming, :unscheduled], do: :neutral

  @spec status_icon(atom()) :: String.t()
  def status_icon(:armed), do: "hero-bolt-mini"
  def status_icon(:armed_fallback), do: "hero-bolt-mini"
  def status_icon(:under_pursuit), do: "hero-arrow-down-tray-mini"
  def status_icon(:in_library), do: "hero-check-circle-mini"
  def status_icon(:theatrical_info), do: "hero-ticket-mini"
  def status_icon(status) when status in [:upcoming, :unscheduled], do: "hero-clock-mini"

  @doc "Tailwind text-colour class for a status tone (status is the only saturated colour on the page)."
  @spec tone_text_class(tone()) :: String.t()
  def tone_text_class(:success), do: "text-success"
  def tone_text_class(:info), do: "text-info"
  def tone_text_class(:muted), do: "text-warning/70"
  def tone_text_class(:neutral), do: "text-base-content/50"

  @doc "Tailwind background class for a status tone (the shelf release dot)."
  @spec tone_dot_class(tone()) :: String.t()
  def tone_dot_class(:success), do: "bg-success"
  def tone_dot_class(:info), do: "bg-info"
  def tone_dot_class(:muted), do: "bg-warning/70"
  def tone_dot_class(:neutral), do: "bg-base-content/40"

  @doc "What this event delivers — an episode code, a season drop, or a movie release type."
  @spec what_drops(Event.t()) :: String.t()
  def what_drops(%Event{kind: :season_drop, season_number: season, episode_count: count}) do
    "Season #{season} · #{count} episodes · full drop"
  end

  def what_drops(%Event{kind: :episode, season_number: season, episode_number: episode}) do
    "S#{pad(season)}E#{pad(episode)}"
  end

  def what_drops(%Event{kind: :movie, release_type: "digital"}), do: "Digital release"
  def what_drops(%Event{kind: :movie, release_type: "physical"}), do: "Physical release"
  def what_drops(%Event{kind: :movie, release_type: "theatrical"}), do: "In theaters"
  def what_drops(%Event{kind: :movie}), do: "Release"

  @doc "Honest theatrical caveat — the app informs, it does not grab."
  @spec theatrical_note?(Event.t()) :: boolean()
  def theatrical_note?(%Event{status: :theatrical_info}), do: true
  def theatrical_note?(%Event{}), do: false

  @doc ~S"""
  Relative-day copy for an air date: "Today" (incl. the recent linger window),
  "Tomorrow", "in N days" out to a week, else an abbreviated month-day.
  """
  @spec relative_day(Date.t(), Date.t()) :: String.t()
  def relative_day(date, today) do
    case Date.diff(date, today) do
      diff when diff <= 0 -> "Today"
      1 -> "Tomorrow"
      diff when diff <= 6 -> "in #{diff} days"
      _ -> Calendar.strftime(date, "%b %-d")
    end
  end

  @doc """
  The auto-grab posture for a title's detail panel — `%{on?, label}`. Honest
  about gating: with acquisition unconfigured nothing grabs regardless of mode.
  """
  @spec auto_grab_summary(String.t() | nil, String.t(), boolean()) ::
          %{on?: boolean(), label: String.t()}
  def auto_grab_summary(_item_mode, _default_mode, false = _acquisition?),
    do: %{on?: false, label: "Acquisition not configured"}

  def auto_grab_summary(item_mode, default_mode, true = _acquisition?) do
    case effective_auto_grab_mode(item_mode, default_mode) do
      "all_releases" -> %{on?: true, label: "Auto-grabbing every release"}
      "ask" -> %{on?: false, label: "Ask before grabbing"}
      _off -> %{on?: false, label: "Not auto-grabbing"}
    end
  end

  @doc "Resolve an item's effective auto-grab mode against the global default."
  @spec effective_auto_grab_mode(String.t() | nil, String.t()) :: String.t()
  def effective_auto_grab_mode(mode, default) when mode in [nil, "global"], do: default
  def effective_auto_grab_mode(mode, _default) when is_binary(mode), do: mode

  @spec bucket_label(atom()) :: String.t()
  def bucket_label(:today), do: "Today"
  def bucket_label(:this_week), do: "This week"
  def bucket_label(:next_week), do: "Next week"
  def bucket_label(:later), do: "Later this month"
  def bucket_label(:beyond), do: "Beyond"

  defp pad(nil), do: "00"
  defp pad(number) when number < 10, do: "0#{number}"
  defp pad(number), do: "#{number}"
end
