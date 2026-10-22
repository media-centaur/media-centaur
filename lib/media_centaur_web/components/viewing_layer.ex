defmodule MediaCentaurWeb.Components.ViewingLayer do
  @moduledoc """
  The viewing layer: the host's page as a remote player's OSD
  (`campaigns/remote-players.md`, M5; mockup direction 3, *scrim and
  seek bar*). The device's mpv draws nothing, so the page over the video
  draws what the desktop's mpv and its bundled scripts draw there — from
  one `Playback.Viewing`.

    * **The bar**: a bottom scrim, the title and episode line, the clock at
      both ends of a full-width seek bar with chapter ticks and a handle.
      On screen while paused and for a few seconds after a key
      (`bar_shown?`), with a pause glyph in the centre while paused.
    * **The prompt**: Skip Intro or Next Episode (`viewing.prompt`) as the
      primary button at the top right with its key hint — the layer's one
      nav item, so SELECT activates it (`viewing_prompt`).
    * **The subtitle line**: `viewing.subtitle_text`, centred above the bar's
      place.
    * **The track menu**: a centred glass modal of two `GlassMenu.menu_list`
      columns, Audio and Subtitles, the active entries marked, *None* first
      in Subtitles, bitmap tracks disabled with "Not on this TV" and a note
      when a file has nothing else (`viewing_track`, `viewing_menu_close`).

  The input contract: the layer root carries `data-viewing` (the page's
  behaviour wraps itself while it is present); the OSD is the active
  overlay (`data-detail-mode="modal"`, BACK pushes `viewing_back`); the
  menu, rendered before it in DOM order, is the active overlay while open
  (`data-nav-overlay="viewing_menu"`, BACK pushes `viewing_menu_close`) and
  is nested in the OSD's (`data-detail-nested`): closing it returns the
  cursor to the OSD rather than ending the page's overlay state.
  Nothing here animates continuously: the seek handle moves with the
  session's 1 Hz tick (measured on the Sony: a 60 fps page animation over
  4K video janks, a 1 Hz bar costs nothing).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Iso639
  alias MediaCentaur.Playback.{TrackResolver.Track, Viewing}
  alias MediaCentaurWeb.Components.GlassMenu

  @codec_labels %{
    "dts" => "DTS",
    "ac3" => "AC3",
    "eac3" => "E-AC3",
    "truehd" => "TrueHD",
    "aac" => "AAC",
    "opus" => "Opus",
    "flac" => "FLAC",
    "mp3" => "MP3",
    "pcm_s16le" => "PCM",
    "pcm_s24le" => "PCM",
    "subrip" => "SRT",
    "ass" => "ASS",
    "ssa" => "SSA",
    "webvtt" => "VTT",
    "mov_text" => "Text",
    "hdmv_pgs_subtitle" => "PGS",
    "dvd_subtitle" => "VobSub",
    "dvb_subtitle" => "DVB"
  }

  attr :viewing, Viewing, required: true, doc: "the player's viewing"

  attr :bar_shown?, :boolean,
    default: false,
    doc: "whether the bar is on screen (paused, or a key was pressed)"

  attr :menu_open?, :boolean, default: false, doc: "whether the track menu is open"

  @doc "The whole layer for one viewing: the track menu, then the OSD over the video."
  def viewing_layer(assigns) do
    ~H"""
    <div id="viewing" class="viewing" data-viewing>
      <.viewing_track_menu viewing={@viewing} open?={@menu_open?} />
      <div
        id="viewing-osd"
        class="viewing-osd"
        data-detail-mode="modal"
        data-dismiss-event="viewing_back"
        data-bar={if @bar_shown?, do: "shown", else: "hidden"}
      >
        <div :if={@viewing.state == :paused} class="viewing-centre" aria-hidden="true">
          <.icon name="hero-pause-solid" class="size-10" />
        </div>
        <.viewing_prompt :if={@viewing.prompt} prompt={@viewing.prompt} />
        <.viewing_subtitle
          :if={@viewing.subtitle_text}
          text={@viewing.subtitle_text}
          lifted={@bar_shown?}
        />
        <.viewing_bar viewing={@viewing} />
      </div>
    </div>
    """
  end

  attr :viewing, Viewing, required: true

  @doc "The bar: scrim, title, episode line, the clock at both ends of the seek bar with chapter ticks."
  def viewing_bar(assigns) do
    assigns =
      assign(assigns,
        percent: percent(assigns.viewing.position_seconds, assigns.viewing.duration_seconds),
        ticks: ticks(assigns.viewing.chapters, assigns.viewing.duration_seconds),
        episode_line: episode_line(assigns.viewing)
      )

    ~H"""
    <div class="viewing-scrim" aria-hidden="true"></div>
    <div class="viewing-bar" data-component="viewing-bar">
      <div :if={@viewing.state == :paused} class="viewing-state">Paused</div>
      <div class="viewing-title text-on-image">{@viewing.entity_name}</div>
      <div :if={@episode_line} class="viewing-episode text-on-image">{@episode_line}</div>
      <div class="viewing-row">
        <span class="viewing-clock">{Format.format_seconds(@viewing.position_seconds)}</span>
        <div
          class="viewing-seek"
          role="progressbar"
          aria-valuenow={@percent}
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <span :for={tick <- @ticks} class="viewing-tick" style={"left: #{tick}%"}></span>
          <i
            class={["viewing-fill", @viewing.state == :paused && "viewing-fill--paused"]}
            style={"width: #{@percent}%"}
          ></i>
          <b class="viewing-handle" style={"left: #{@percent}%"}></b>
        </div>
        <span class="viewing-clock">{Format.format_seconds(@viewing.duration_seconds)}</span>
      </div>
    </div>
    """
  end

  attr :prompt, :any,
    required: true,
    doc: "`Viewing.prompt/0`: Skip Intro, Next Episode or the countdown"

  @doc "The prompt pill at the top right: the layer's one nav item, with its key hint."
  def viewing_prompt(assigns) do
    ~H"""
    <.button
      id="viewing-prompt"
      variant="primary"
      size="lg"
      class="viewing-prompt"
      phx-click="viewing_prompt"
      data-nav-item
      data-viewing-prompt
      tabindex="0"
    >
      <kbd class="viewing-key">OK</kbd>
      {prompt_label(@prompt)}
      <.icon name="hero-forward-solid" class="size-5" />
    </.button>
    """
  end

  attr :text, :string, required: true
  attr :lifted, :boolean, default: false, doc: "above the bar while the bar shows"

  @doc "The current subtitle line, plain text over the picture."
  def viewing_subtitle(assigns) do
    ~H"""
    <div class={["viewing-subtitle text-on-image", @lifted && "viewing-subtitle--lifted"]}>
      <span :for={line <- String.split(@text, "\n")} class="block">{line}</span>
    </div>
    """
  end

  attr :viewing, Viewing, required: true
  attr :open?, :boolean, default: false

  @doc "The track menu: Audio and Subtitles as two menu lists in a centred glass modal; bitmap tracks disabled."
  def viewing_track_menu(assigns) do
    assigns = assign(assigns, bitmap_only?: bitmap_only?(assigns.viewing.subtitle_tracks))

    ~H"""
    <div
      id="viewing-menu"
      class="viewing-menu-backdrop"
      data-state={if @open?, do: "open", else: "closed"}
      data-detail-mode={@open? && "modal"}
      data-detail-nested="true"
      data-dismiss-event="viewing_menu_close"
      data-nav-overlay="viewing_menu"
    >
      <div class="viewing-menu glass-surface">
        <h2 class="viewing-menu-title">Audio &amp; subtitles</h2>
        <div class="viewing-menu-columns">
          <div class="viewing-menu-column">
            <h3 class="viewing-menu-heading">Audio</h3>
            <GlassMenu.menu_list
              id="viewing-audio"
              zone="viewing_audio"
              on_close="viewing_menu_close"
              class="viewing-menu-list"
            >
              <:item
                :for={track <- @viewing.audio_tracks}
                id={"viewing-audio-#{track.index}"}
                event="viewing_track"
                values={%{"kind" => "audio", "id" => to_string(track.index)}}
                active={track.index == @viewing.aid}
              >
                <span class="viewing-menu-label">{track_label(track)}</span>
                <span class="viewing-menu-meta">{codec_label(track)}</span>
              </:item>
            </GlassMenu.menu_list>
          </div>
          <div class="viewing-menu-column">
            <h3 class="viewing-menu-heading">Subtitles</h3>
            <GlassMenu.menu_list
              id="viewing-subtitles"
              zone="viewing_subtitles"
              on_close="viewing_menu_close"
              class="viewing-menu-list"
            >
              <:item
                id="viewing-subtitles-none"
                event="viewing_track"
                values={%{"kind" => "subtitle", "id" => "none"}}
                active={subtitles_off?(@viewing.sid)}
              >
                <span class="viewing-menu-label">None</span>
              </:item>
              <:item
                :for={track <- @viewing.subtitle_tracks}
                id={"viewing-subtitles-#{track.index}"}
                event="viewing_track"
                values={%{"kind" => "subtitle", "id" => to_string(track.index)}}
                active={track.index == @viewing.sid}
                disabled={Viewing.bitmap_track?(track)}
              >
                <span class="viewing-menu-label">{track_label(track)}</span>
                <span class="viewing-menu-meta">
                  {if Viewing.bitmap_track?(track), do: "Not on this TV", else: codec_label(track)}
                </span>
              </:item>
            </GlassMenu.menu_list>
          </div>
        </div>
        <p :if={@bitmap_only?} class="viewing-menu-note">
          This file's subtitles are images (PGS), which the TV player cannot draw. Text subtitles would show here.
        </p>
        <div class="viewing-menu-hint">
          <kbd class="viewing-key">◀ ▶</kbd>
          column <kbd class="viewing-key">▲ ▼</kbd>
          choose <kbd class="viewing-key">OK</kbd>
          apply <kbd class="viewing-key">BACK</kbd>
          close
        </div>
      </div>
    </div>
    """
  end

  # --- labels ---

  @doc false
  def prompt_label({:skip_intro, _target}), do: "Skip Intro"
  def prompt_label(:next_episode), do: "Next Episode"
  def prompt_label({:next_episode_in, seconds}), do: "Next episode in #{seconds} s"

  defp episode_line(%Viewing{season_number: season, episode_number: episode, episode_name: name})
       when is_integer(season) and is_integer(episode) do
    Enum.join(["S#{season} E#{episode}", name], " · ")
  end

  defp episode_line(%Viewing{episode_name: name}) when is_binary(name), do: name
  defp episode_line(_viewing), do: nil

  defp percent(position, duration) when is_number(duration) and duration > 0,
    do: Float.round(min(max(position / duration * 100, 0), 100), 2)

  defp percent(_position, _duration), do: 0

  defp ticks(chapters, duration) when is_list(chapters) and is_number(duration) and duration > 0 do
    chapters
    |> Enum.map(&(Map.get(&1, "time") || Map.get(&1, :time)))
    |> Enum.filter(&(is_number(&1) and &1 > 0 and &1 < duration))
    |> Enum.map(&Float.round(&1 / duration * 100, 2))
  end

  defp ticks(_chapters, _duration), do: []

  defp track_label(%Track{title: title}) when is_binary(title) and title != "", do: title

  defp track_label(%Track{lang: lang}) when is_binary(lang), do: Iso639.display_name(lang)

  defp track_label(%Track{index: index}), do: "Track #{index}"

  defp codec_label(%Track{codec: codec}),
    do: Map.get(@codec_labels, codec, codec && String.upcase(codec))

  defp subtitles_off?(sid), do: sid in [nil, false, "no"]

  defp bitmap_only?([]), do: false
  defp bitmap_only?(tracks), do: Enum.all?(tracks, &Viewing.bitmap_track?/1)
end
