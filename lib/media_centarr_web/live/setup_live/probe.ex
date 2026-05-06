defmodule MediaCentarrWeb.Live.SetupLive.Probe do
  @moduledoc """
  Probe result struct for the Setup Tour.

  A `%Probe.Result{}` summarises one dependency check — used by both the
  Setup Tour wizard (as a step) and the Settings → Overview health card
  (as a row). Probes are pure: they read the loaded config and observe
  the filesystem, but never call out to network services. Network
  "Test now" actions live on the wizard step itself.
  """

  defmodule Result do
    @moduledoc "One probe outcome — see `MediaCentarrWeb.Live.SetupLive.Probe`."

    @enforce_keys [:id, :status, :critical?]
    defstruct [
      :id,
      :status,
      :detail,
      :current_value,
      :detected_candidates,
      :critical?
    ]

    @type id ::
            :watch_dirs | :tmdb | :mpv | :ffprobe | :prowlarr | :download_client
    @type status :: :ok | :warning | :error | :not_configured

    @type t :: %__MODULE__{
            id: id(),
            status: status(),
            detail: String.t() | nil,
            current_value: any(),
            detected_candidates: [String.t()] | nil,
            critical?: boolean()
          }
  end
end
