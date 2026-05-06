defmodule MediaCentarrWeb.Live.SetupLive.Probes do
  @moduledoc """
  Pure probe functions for the Setup Tour. Each function takes a flat
  input map (the same shape Overview already builds) and returns one
  `Probe.Result`. `all/1` returns the full list in step order.

  Probes never block on network. "Test connection" actions for TMDB,
  Prowlarr, and the download client are separate events triggered by
  buttons on the wizard step — they update an in-memory ConnectionTest
  result, not the probe itself.
  """

  alias MediaCentarrWeb.Live.SettingsLive.PathCheck
  alias MediaCentarrWeb.Live.SetupLive.{BinaryDetector, Probe}

  @step_order [:watch_dirs, :tmdb, :mpv, :ffprobe, :prowlarr, :download_client]

  @doc "Returns the canonical step order for the wizard."
  @spec step_order() :: [Probe.Result.id()]
  def step_order, do: @step_order

  @doc "Builds the full list of probe results in step order."
  @spec all(map()) :: [Probe.Result.t()]
  def all(input) do
    [
      watch_dirs(Map.get(input, :watch_dirs_entries, [])),
      tmdb(input),
      mpv(input),
      ffprobe(input),
      prowlarr(input),
      download_client(input)
    ]
  end

  # --- TMDB ---

  @spec tmdb(map()) :: Probe.Result.t()
  def tmdb(%{tmdb_api_key_configured?: true}) do
    %Probe.Result{
      id: :tmdb,
      status: :ok,
      detail: "API key configured",
      critical?: true
    }
  end

  def tmdb(_input) do
    %Probe.Result{
      id: :tmdb,
      status: :not_configured,
      detail: "Without TMDB, no metadata will be fetched.",
      critical?: true
    }
  end

  # --- mpv ---

  @spec mpv(map()) :: Probe.Result.t()
  def mpv(input) do
    binary_probe(:mpv, input[:mpv_path], "mpv",
      paths: input[:binary_paths],
      name_override: input[:binary_name_override],
      critical?: false,
      not_configured_detail: "Without mpv, playback is disabled.",
      ok_detail: fn path -> path end
    )
  end

  # --- ffprobe ---

  @spec ffprobe(map()) :: Probe.Result.t()
  def ffprobe(input) do
    binary_probe(:ffprobe, input[:ffprobe_path], "ffprobe",
      paths: input[:binary_paths],
      name_override: input[:binary_name_override],
      critical?: false,
      not_configured_detail: "Without ffprobe, embedded subtitles can't be detected.",
      ok_detail: fn path -> path end
    )
  end

  # --- Prowlarr ---

  @spec prowlarr(map()) :: Probe.Result.t()
  def prowlarr(%{prowlarr_api_key_configured?: true}) do
    %Probe.Result{
      id: :prowlarr,
      status: :ok,
      detail: "API key configured",
      critical?: false
    }
  end

  def prowlarr(_input) do
    %Probe.Result{
      id: :prowlarr,
      status: :not_configured,
      detail: "Optional — needed for in-app indexer search.",
      critical?: false
    }
  end

  # --- Download client ---

  @spec download_client(map()) :: Probe.Result.t()
  def download_client(%{download_client_password_configured?: true}) do
    %Probe.Result{
      id: :download_client,
      status: :ok,
      detail: "Credentials configured",
      critical?: false
    }
  end

  def download_client(_input) do
    %Probe.Result{
      id: :download_client,
      status: :not_configured,
      detail: "Optional — needed to track download progress.",
      critical?: false
    }
  end

  # --- Watch dirs ---

  @spec watch_dirs([map()]) :: Probe.Result.t()
  def watch_dirs([]) do
    %Probe.Result{
      id: :watch_dirs,
      status: :not_configured,
      detail: "No watch directories — the library will stay empty.",
      current_value: [],
      critical?: true
    }
  end

  def watch_dirs(entries) when is_list(entries) do
    dirs = Enum.map(entries, & &1["dir"])
    missing = Enum.count(dirs, &(PathCheck.check(&1, :directory) != :ok))
    total = length(dirs)

    {status, detail} =
      cond do
        missing == 0 ->
          {:ok, describe_dirs(total)}

        missing == total ->
          {:error, "All #{total} watch directories are unreachable."}

        true ->
          {:warning, "#{missing} of #{total} watch directories unreachable."}
      end

    %Probe.Result{
      id: :watch_dirs,
      status: status,
      detail: detail,
      current_value: entries,
      critical?: true
    }
  end

  defp describe_dirs(1), do: "1 directory configured."
  defp describe_dirs(n), do: "#{n} directories configured."

  # --- shared binary probe ---

  defp binary_probe(id, path, default_name, opts) do
    custom_paths = Keyword.get(opts, :paths)
    name_override = Keyword.get(opts, :name_override)
    critical? = Keyword.fetch!(opts, :critical?)
    not_configured_detail = Keyword.fetch!(opts, :not_configured_detail)
    ok_detail = Keyword.fetch!(opts, :ok_detail)

    detect_name = name_override || default_name

    candidates =
      case custom_paths do
        nil -> BinaryDetector.detect(detect_name)
        paths when is_list(paths) -> BinaryDetector.detect(detect_name, paths)
      end

    case path do
      nil ->
        %Probe.Result{
          id: id,
          status: :not_configured,
          detail: not_configured_detail,
          current_value: nil,
          detected_candidates: candidates,
          critical?: critical?
        }

      "" ->
        %Probe.Result{
          id: id,
          status: :not_configured,
          detail: not_configured_detail,
          current_value: nil,
          detected_candidates: candidates,
          critical?: critical?
        }

      configured ->
        case PathCheck.check(configured, :executable) do
          :ok ->
            %Probe.Result{
              id: id,
              status: :ok,
              detail: ok_detail.(configured),
              current_value: configured,
              detected_candidates: candidates,
              critical?: critical?
            }

          :not_executable ->
            %Probe.Result{
              id: id,
              status: :error,
              detail: "File exists but is not executable: #{configured}",
              current_value: configured,
              detected_candidates: candidates,
              critical?: critical?
            }

          _ ->
            %Probe.Result{
              id: id,
              status: :error,
              detail: "Not found: #{configured}",
              current_value: configured,
              detected_candidates: candidates,
              critical?: critical?
            }
        end
    end
  end
end
