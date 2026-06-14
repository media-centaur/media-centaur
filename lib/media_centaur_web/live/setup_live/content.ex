defmodule MediaCentaurWeb.Live.SetupLive.Content do
  @moduledoc """
  Per-step copy for the Setup Tour. Consolidated here so step
  components stay focused on layout and copy edits don't touch logic.

  Each probe id maps to a `%Content{}` with:
  - `title` — full step heading
  - `short` — one-line subtitle ("Where your video files live")
  - `requirements` — bullet list of what the user needs on hand to set it up

  The copy is deliberately terse: a first-run user needs to know what to
  provide to get this piece working, not an essay on what the dependency is.
  """

  @enforce_keys [:title, :short, :requirements]
  defstruct [:title, :short, :requirements]

  @type t :: %__MODULE__{
          title: String.t(),
          short: String.t(),
          requirements: [String.t()]
        }

  @doc "Returns the `%Content{}` for the given probe id."
  @spec for(atom()) :: t()
  def for(:media_dirs) do
    %__MODULE__{
      title: "Media directories",
      short: "Where your video files live",
      requirements: [
        "An absolute path to a folder of video files — e.g. /mnt/media/Movies",
        "Read access for the user running Media Centaur"
      ]
    }
  end

  def for(:tmdb) do
    %__MODULE__{
      title: "TMDB",
      short: "Metadata, posters, and release tracking",
      requirements: [
        "A free account at themoviedb.org",
        "Your v4 read-access token from Settings → API"
      ]
    }
  end

  def for(:mpv) do
    %__MODULE__{
      title: "mpv",
      short: "The media player",
      requirements: [
        "mpv installed — pacman / apt / brew install mpv",
        "The path to the binary — auto-detected on common locations"
      ]
    }
  end

  def for(:ffprobe) do
    %__MODULE__{
      title: "ffprobe",
      short: "Embedded subtitle detection (optional)",
      requirements: [
        "ffmpeg installed — ffprobe ships with it",
        "The path to ffprobe — auto-detected on common locations"
      ]
    }
  end

  def for(:prowlarr) do
    %__MODULE__{
      title: "Prowlarr",
      short: "In-app indexer search (optional)",
      requirements: [
        "A running Prowlarr instance (default port 9696)",
        "Its base URL — e.g. http://localhost:9696",
        "Your Prowlarr API key — Settings → General"
      ]
    }
  end

  def for(:download_client) do
    %__MODULE__{
      title: "Download client",
      short: "Track download progress (optional)",
      requirements: [
        "A running qBittorrent — the supported default",
        "Its Web UI URL — e.g. http://localhost:8080",
        "The username and password it accepts"
      ]
    }
  end
end
