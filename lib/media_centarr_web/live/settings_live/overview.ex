defmodule MediaCentarrWeb.Live.SettingsLive.Overview do
  @moduledoc """
  Builds the list of health items shown on Settings > Overview.

  Pure function — takes a flat input map (the assigns plus the loaded
  config) and returns a list of grouped items. Tested in isolation under
  `async: true`; the LiveView just renders whatever this returns.

  ## Item shape

      %{
        id: atom,
        label: "Human label",
        detail: "One-line status / value",
        status: :ok | :warning | :error | :neutral,
        link: "/settings?section=..."
      }

  Status semantics:
  - `:ok` — everything is fine, nothing to act on
  - `:warning` — configured but a secondary check failed or partial state
  - `:error` — not configured at all; a major feature is disabled
  - `:neutral` — informational (e.g. a running-vs-stopped indicator where
    "stopped" is a legitimate user choice, not a problem)
  """

  alias MediaCentarrWeb.Live.SettingsLive.{ConnectionTest, PathCheck}

  @type status :: :ok | :warning | :error | :neutral

  @type item :: %{
          id: atom(),
          label: String.t(),
          detail: String.t(),
          status: status(),
          link: String.t()
        }

  @type group :: %{id: atom(), label: String.t(), items: [item()]}

  @doc "Builds the list of health-item groups from settings input."
  @spec build(map()) :: [group()]
  def build(input) do
    [
      services_group(input),
      configuration_group(input),
      storage_group(input)
    ]
  end

  @doc "Counts items whose status is `:warning` or `:error`."
  @spec issue_count([group()]) :: non_neg_integer()
  def issue_count(groups) do
    groups
    |> Enum.flat_map(& &1.items)
    |> Enum.count(&(&1.status in [:warning, :error]))
  end

  # --- Services ---

  defp services_group(input) do
    %{
      id: :services,
      label: "Services",
      items: [
        service_item(:watchers, "Watchers", input.watchers_running),
        service_item(:pipeline, "Pipeline", input.pipeline_running),
        service_item(:image_pipeline, "Image Pipeline", input.image_pipeline_running)
      ]
    }
  end

  defp service_item(id, label, true) do
    %{id: id, label: label, detail: "Running", status: :ok, link: section_link("services")}
  end

  defp service_item(id, label, false) do
    %{
      id: id,
      label: label,
      detail: "Stopped",
      status: :warning,
      link: section_link("services")
    }
  end

  # --- Configuration ---

  defp configuration_group(input) do
    config = input.config

    %{
      id: :configuration,
      label: "Configuration",
      items: [
        tmdb_item(config),
        prowlarr_item(config, input[:prowlarr_test]),
        download_client_item(config, input[:download_client_test]),
        mpv_item(config)
      ]
    }
  end

  defp tmdb_item(%{tmdb_api_key_configured?: true}) do
    %{
      id: :tmdb,
      label: "TMDB",
      detail: "Configured",
      status: :ok,
      link: section_link("tmdb")
    }
  end

  defp tmdb_item(_config) do
    %{
      id: :tmdb,
      label: "TMDB",
      detail: "Not configured — metadata scraping is disabled",
      status: :error,
      link: section_link("tmdb")
    }
  end

  defp prowlarr_item(%{prowlarr_api_key_configured?: true}, test) do
    connected_item(:prowlarr, "Prowlarr", test, section_link("acquisition"),
      error_detail: "Unreachable — check URL and API key"
    )
  end

  defp prowlarr_item(_config, _test) do
    %{
      id: :prowlarr,
      label: "Prowlarr",
      detail: "Not configured — media acquisition is disabled",
      status: :error,
      link: section_link("acquisition")
    }
  end

  defp download_client_item(%{download_client_password_configured?: true}, test) do
    connected_item(:download_client, "Download Client", test, section_link("acquisition"),
      error_detail: "Unreachable — URL or credentials wrong"
    )
  end

  defp download_client_item(_config, _test) do
    %{
      id: :download_client,
      label: "Download Client",
      detail: "Not configured — downloads cannot be tracked",
      status: :error,
      link: section_link("acquisition")
    }
  end

  # Shared "configured + test result" handler.
  defp connected_item(id, label, nil, link, _opts) do
    %{
      id: id,
      label: label,
      detail: "Configured — not tested",
      status: :ok,
      link: link
    }
  end

  defp connected_item(id, label, %{status: :ok, tested_at: tested_at}, link, _opts) do
    age = ConnectionTest.relative_age(tested_at)

    %{
      id: id,
      label: label,
      detail: "Connected (tested #{age})",
      status: :ok,
      link: link
    }
  end

  defp connected_item(id, label, %{status: :error, tested_at: tested_at}, link, opts) do
    age = ConnectionTest.relative_age(tested_at)

    %{
      id: id,
      label: label,
      detail: "#{Keyword.fetch!(opts, :error_detail)} (as of #{age})",
      status: :warning,
      link: link
    }
  end

  defp mpv_item(%{mpv_path: path}) when is_binary(path) do
    case PathCheck.check(path, :executable) do
      :ok ->
        %{
          id: :mpv,
          label: "MPV binary",
          detail: path,
          status: :ok,
          link: section_link("playback")
        }

      :not_executable ->
        %{
          id: :mpv,
          label: "MPV binary",
          detail: "File exists but is not executable: #{path}",
          status: :error,
          link: section_link("playback")
        }

      _ ->
        %{
          id: :mpv,
          label: "MPV binary",
          detail: "Not found — playback is disabled",
          status: :error,
          link: section_link("playback")
        }
    end
  end

  defp mpv_item(_config) do
    %{
      id: :mpv,
      label: "MPV binary",
      detail: "No path configured",
      status: :error,
      link: section_link("playback")
    }
  end

  # --- Storage ---

  defp storage_group(input) do
    config = input.config

    %{
      id: :storage,
      label: "Storage",
      items: [
        database_item(config),
        watch_dirs_item(config)
      ]
    }
  end

  defp database_item(%{database_path: path}) when is_binary(path) do
    dir = Path.dirname(path)

    case PathCheck.check(dir, :directory) do
      :ok ->
        %{
          id: :database,
          label: "Database",
          detail: truncate(path),
          status: :ok,
          link: section_link("overview")
        }

      _ ->
        %{
          id: :database,
          label: "Database",
          detail: "Parent directory missing: #{dir}",
          status: :warning,
          link: section_link("overview")
        }
    end
  end

  defp database_item(_config) do
    %{
      id: :database,
      label: "Database",
      detail: "No path configured",
      status: :warning,
      link: section_link("overview")
    }
  end

  defp watch_dirs_item(%{watch_dirs: nil}), do: watch_dirs_item(%{watch_dirs: []})

  defp watch_dirs_item(%{} = config) when not is_map_key(config, :watch_dirs),
    do: watch_dirs_item(%{watch_dirs: []})

  defp watch_dirs_item(%{watch_dirs: []}) do
    %{
      id: :watch_dirs,
      label: "Watch directories",
      detail: "None configured",
      status: :warning,
      link: section_link("overview")
    }
  end

  defp watch_dirs_item(%{watch_dirs: dirs}) when is_list(dirs) do
    missing = Enum.count(dirs, &(PathCheck.check(&1, :directory) != :ok))

    cond do
      missing == 0 ->
        %{
          id: :watch_dirs,
          label: "Watch directories",
          detail: describe_dirs(dirs),
          status: :ok,
          link: section_link("overview")
        }

      missing == length(dirs) ->
        %{
          id: :watch_dirs,
          label: "Watch directories",
          detail: "All #{length(dirs)} unreachable — check that storage is mounted",
          status: :warning,
          link: section_link("overview")
        }

      true ->
        %{
          id: :watch_dirs,
          label: "Watch directories",
          detail: "#{missing} of #{length(dirs)} unreachable",
          status: :warning,
          link: section_link("overview")
        }
    end
  end

  defp describe_dirs([dir]), do: truncate(dir)
  defp describe_dirs(dirs), do: "#{length(dirs)} reachable"

  defp truncate(path) when byte_size(path) <= 48, do: path
  defp truncate(path), do: "…" <> binary_part(path, byte_size(path) - 47, 47)

  defp section_link(section), do: "/settings?section=#{section}"
end
