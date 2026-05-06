defmodule MediaCentarrWeb.Live.SetupLive.Content do
  @moduledoc """
  Per-step copy for the Setup Tour. Consolidated here so step
  components stay focused on layout and copy edits don't touch logic.

  Each probe id maps to a `%Content{}` with:
  - `title` — full step heading
  - `short` — one-line subtitle ("Where your video files live")
  - `what` — paragraph explaining what this dependency is
  - `why` — paragraph explaining why it matters
  - `requirements` — bullet list of what the user needs on hand
  """

  @enforce_keys [:title, :short, :what, :why, :requirements]
  defstruct [:title, :short, :what, :why, :requirements]

  @type t :: %__MODULE__{
          title: String.t(),
          short: String.t(),
          what: String.t(),
          why: String.t(),
          requirements: [String.t()]
        }

  @doc "Returns the `%Content{}` for the given probe id."
  @spec for(atom()) :: t()
  def for(:watch_dirs) do
    %__MODULE__{
      title: "Watch directories",
      short: "Where your video files live",
      what:
        "Watch directories are the folders Media Centarr scans for video files. " <>
          "It checks each one continuously and identifies new arrivals via TMDB. " <>
          "You can have one or many — typical setups separate movies and TV onto different drives.",
      why:
        "Without at least one watch directory, your library stays empty. " <>
          "This is the foundation everything else builds on.",
      requirements: [
        "An absolute path to a folder containing video files (e.g. /mnt/media/Movies)",
        "Read access to that folder for the user running Media Centarr"
      ]
    }
  end

  def for(:tmdb) do
    %__MODULE__{
      title: "TMDB",
      short: "Metadata, posters, and release tracking",
      what:
        "The Movie Database is the source of all metadata Media Centarr displays — titles, " <>
          "descriptions, posters, backdrops, cast, episode lists, air dates. The app talks to it " <>
          "via your personal API key.",
      why:
        "Without a working TMDB key the pipeline can't identify your files, no artwork is " <>
          "downloaded, and Upcoming / Tracking features are disabled. Strongly recommended.",
      requirements: [
        "A free TMDB account at themoviedb.org",
        "Your v4 read-access token from the API settings page"
      ]
    }
  end

  def for(:mpv) do
    %__MODULE__{
      title: "mpv",
      short: "The media player",
      what:
        "mpv is the playback engine Media Centarr launches when you press Play. The app " <>
          "controls it over a Unix socket — pause, seek, change subtitle track — and reads " <>
          "playback progress back to update your watch history.",
      why: "Without a working mpv binary, playback is disabled. Library browsing still works.",
      requirements: [
        "mpv installed on this machine — `pacman -S mpv`, `apt install mpv`, " <>
          "`brew install mpv`, or your distro's equivalent",
        "An absolute path to the binary — Media Centarr can auto-detect common locations"
      ]
    }
  end

  def for(:ffprobe) do
    %__MODULE__{
      title: "ffprobe",
      short: "Embedded subtitle detection (optional)",
      what:
        "ffprobe (part of the FFmpeg toolkit) reads the metadata stream of a video file. " <>
          "Media Centarr uses it to discover embedded subtitle tracks inside MKV/MP4 containers " <>
          "without playing the file.",
      why:
        "Subtitles still work without ffprobe — sidecar files like `movie.en.srt` are detected " <>
          "by filename and play normally. What you lose is visibility into tracks embedded " <>
          "inside the video container itself: they're invisible to the library UI until you " <>
          "launch the file in mpv. Skip this step if all your subtitles are already sidecar files.",
      requirements: [
        "ffmpeg installed on this machine (ffprobe ships with it) — `pacman -S ffmpeg`, " <>
          "`apt install ffmpeg`, `brew install ffmpeg`",
        "An absolute path to the ffprobe binary — auto-detected on common paths"
      ]
    }
  end

  def for(:prowlarr) do
    %__MODULE__{
      title: "Prowlarr",
      short: "In-app indexer search (optional)",
      what:
        "Prowlarr is a separate self-hosted service that aggregates torrent / Usenet indexers " <>
          "behind a single API. Media Centarr talks to it for searches initiated from the " <>
          "Downloads page or 'Track new releases' actions.",
      why:
        "Optional. Skip this step if you don't use Prowlarr — manual library management still " <>
          "works perfectly. Configure it later if you want in-app search.",
      requirements: [
        "A running Prowlarr instance (default port 9696)",
        "The base URL — e.g. http://localhost:9696",
        "Your Prowlarr API key from Settings → General"
      ]
    }
  end

  def for(:download_client) do
    %__MODULE__{
      title: "Download client",
      short: "Track download progress (optional)",
      what:
        "Once Prowlarr forwards a grab to a download client (qBittorrent, Transmission, etc.), " <>
          "Media Centarr talks to that client directly to read progress: percentage, ETA, status. " <>
          "Without this, grabs disappear after Prowlarr hands them off.",
      why:
        "Optional. Skip if you don't use Prowlarr or you're fine watching downloads in the " <>
          "client's own UI. Required only for the in-app progress widgets.",
      requirements: [
        "A running download client (qBittorrent is the supported default)",
        "The web UI URL — e.g. http://localhost:8080",
        "Username and password the client accepts"
      ]
    }
  end
end
