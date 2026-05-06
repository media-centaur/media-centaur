defmodule MediaCentarrWeb.SetupLive do
  @moduledoc """
  Setup Tour wizard at `/setup`. Walks the user through every dependency
  the app cares about — watch directories, TMDB, mpv, ffprobe, Prowlarr,
  download client. Auto-launched on first run by `SetupRedirect`, also
  reachable anytime from Settings → Overview.

  Step state lives in the URL query string (`?step=<id>`), so browser
  back/forward works and individual steps are deep-linkable. Probes are
  re-run on every patch — they're pure and cheap.

  Connection-test buttons (TMDB / Prowlarr / download client) kick off
  async tasks via `Task.Supervisor` and surface the result as a flash.
  """

  use MediaCentarrWeb, :live_view

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.Prowlarr, as: ProwlarrClient
  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Config
  alias MediaCentarr.Secret
  alias MediaCentarrWeb.Components.SetupSteps
  alias MediaCentarrWeb.Live.SetupLive.{Content, Probes}

  # Tour steps in order. `:welcome` and `:summary` are wrapper steps
  # owned by this LiveView (no probe). The middle slice is sourced from
  # `Probes.step_order/0` so the probe-list and step-list stay in sync.
  @step_order [:welcome] ++ Probes.step_order() ++ [:summary]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_step: hd(@step_order), probes: [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    probes = Probes.all(probe_input())
    step_id = parse_step(params["step"])

    {:noreply, assign(socket, probes: probes, current_step: step_id)}
  end

  defp parse_step(nil), do: hd(@step_order)
  defp parse_step(""), do: hd(@step_order)

  defp parse_step(string) when is_binary(string) do
    case Enum.find(@step_order, &(Atom.to_string(&1) == string)) do
      nil -> hd(@step_order)
      atom -> atom
    end
  end

  # ---------------------------------------------------------------------------
  # Navigation events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("setup:next", _params, socket) do
    case advance(socket.assigns.current_step, +1) do
      :finish -> finish(socket)
      step -> {:noreply, push_patch(socket, to: step_path(step))}
    end
  end

  def handle_event("setup:back", _params, socket) do
    case advance(socket.assigns.current_step, -1) do
      :finish -> {:noreply, socket}
      step -> {:noreply, push_patch(socket, to: step_path(step))}
    end
  end

  def handle_event("setup:skip", _params, socket) do
    handle_event("setup:next", %{}, socket)
  end

  # ---------------------------------------------------------------------------
  # Save-path event (binary steps — mpv / ffprobe)
  # ---------------------------------------------------------------------------

  def handle_event("setup:save_path", %{"id" => id, "path" => path}, socket) do
    save_binary_path(id, path)
    {:noreply, refresh_probes(socket)}
  end

  def handle_event("setup:save_path", %{"path" => path} = params, socket) do
    id = params["id"] || Atom.to_string(socket.assigns.current_step)
    save_binary_path(id, path)
    {:noreply, refresh_probes(socket)}
  end

  # ---------------------------------------------------------------------------
  # Re-check (re-run probes only)
  # ---------------------------------------------------------------------------

  def handle_event("setup:recheck", _params, socket) do
    {:noreply, refresh_probes(socket)}
  end

  # ---------------------------------------------------------------------------
  # Watch dirs
  # ---------------------------------------------------------------------------

  def handle_event("setup:add_watch_dir", %{"dir" => dir}, socket) do
    expanded = Path.expand(dir)
    entries = Config.watch_dirs_entries()

    if !Enum.any?(entries, &(&1["dir"] == expanded)) do
      new_entry = %{
        "id" => Ecto.UUID.generate(),
        "dir" => expanded,
        "images_dir" => nil,
        "name" => nil
      }

      Config.put_watch_dirs(entries ++ [new_entry])
    end

    {:noreply, refresh_probes(socket)}
  end

  def handle_event("setup:remove_watch_dir", %{"dir" => dir}, socket) do
    entries = Enum.reject(Config.watch_dirs_entries(), &(&1["dir"] == dir))
    Config.put_watch_dirs(entries)
    {:noreply, refresh_probes(socket)}
  end

  # ---------------------------------------------------------------------------
  # Save form fields for an integration (TMDB / Prowlarr / download client)
  # ---------------------------------------------------------------------------

  def handle_event("setup:save_integration", params, socket) do
    Enum.each(params, fn
      {"_target", _} ->
        :ok

      {key, value} when is_binary(key) ->
        save_integration_field(key, value)

      _ ->
        :ok
    end)

    ProwlarrClient.invalidate_client()
    QBittorrent.invalidate_client()
    MediaCentarr.TMDB.Client.invalidate_client()

    {:noreply, refresh_probes(socket)}
  end

  # ---------------------------------------------------------------------------
  # Test connection
  # ---------------------------------------------------------------------------

  def handle_event("setup:test_connection", %{"id" => id}, socket) do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      result = run_connection_test(id)
      send(parent, {:setup_test_result, id, result})
    end)

    {:noreply, put_flash(socket, :info, "Testing #{id}…")}
  end

  @impl true
  def handle_info({:setup_test_result, id, :ok}, socket) do
    {:noreply, put_flash(socket, :info, "#{id}: connection verified ✓")}
  end

  def handle_info({:setup_test_result, id, {:error, _}}, socket) do
    {:noreply, put_flash(socket, :error, "#{id}: connection failed")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp probe_input do
    %{
      tmdb_api_key_configured?: Secret.present?(Config.get(:tmdb_api_key)),
      prowlarr_api_key_configured?: Secret.present?(Config.get(:prowlarr_api_key)),
      download_client_password_configured?: Secret.present?(Config.get(:download_client_password)),
      mpv_path: Config.get(:mpv_path),
      ffprobe_path: Config.get(:ffprobe_path),
      watch_dirs_entries: Config.watch_dirs_entries()
    }
  end

  defp refresh_probes(socket) do
    assign(socket, probes: Probes.all(probe_input()))
  end

  defp advance(current, delta) do
    index = Enum.find_index(@step_order, &(&1 == current))
    new_index = index + delta

    cond do
      new_index < 0 -> :finish
      new_index >= length(@step_order) -> :finish
      true -> Enum.at(@step_order, new_index)
    end
  end

  defp step_path(step), do: "/setup?step=#{step}"

  defp finish(socket) do
    Config.update(:setup_wizard_dismissed, true)
    {:noreply, push_navigate(socket, to: "/")}
  end

  defp step_index(step), do: Enum.find_index(@step_order, &(&1 == step)) + 1

  defp current_probe(probes, step), do: Enum.find(probes, &(&1.id == step))

  defp save_binary_path("mpv", path), do: Config.update(:mpv_path, path)
  defp save_binary_path("ffprobe", path), do: Config.update(:ffprobe_path, path)
  defp save_binary_path(_, _), do: :ok

  defp save_integration_field("tmdb_api_key", ""), do: :ok
  defp save_integration_field("tmdb_api_key", value), do: Config.update(:tmdb_api_key, value)
  defp save_integration_field("prowlarr_url", value), do: Config.update(:prowlarr_url, value)
  defp save_integration_field("prowlarr_api_key", ""), do: :ok

  defp save_integration_field("prowlarr_api_key", value), do: Config.update(:prowlarr_api_key, value)

  defp save_integration_field("download_client_type", value),
    do: Config.update(:download_client_type, value)

  defp save_integration_field("download_client_url", value),
    do: Config.update(:download_client_url, value)

  defp save_integration_field("download_client_username", value),
    do: Config.update(:download_client_username, value)

  defp save_integration_field("download_client_password", ""), do: :ok

  defp save_integration_field("download_client_password", value),
    do: Config.update(:download_client_password, value)

  defp save_integration_field(_, _), do: :ok

  defp run_connection_test("tmdb") do
    case MediaCentarr.TMDB.Client.configuration() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_connection_test("prowlarr") do
    case Acquisition.test_prowlarr() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_connection_test("download_client") do
    case Acquisition.test_download_client() do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_connection_test(_), do: {:error, :unsupported}

  defp prowlarr_url, do: Config.get(:prowlarr_url) || ""

  defp download_client_type, do: Config.get(:download_client_type) || "qbittorrent"

  defp download_client_url, do: Config.get(:download_client_url) || ""

  defp download_client_username, do: Config.get(:download_client_username) || ""

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    step_index = step_index(assigns.current_step)
    total = length(@step_order)

    assigns =
      assigns
      |> assign(:probe, current_probe(assigns.probes, assigns.current_step))
      |> assign(:content, content_for(assigns.current_step))
      |> assign(:step_index, step_index)
      |> assign(:total, total)

    ~H"""
    <div class="py-8 px-4 max-w-3xl mx-auto">
      <h1 class="text-3xl font-semibold mb-6">Setup tour</h1>

      <.step_for
        step={@current_step}
        probe={@probe}
        probes={@probes}
        content={@content}
        step_index={@step_index}
        total={@total}
      />
    </div>
    """
  end

  # Welcome / summary steps have no probe → no content lookup. Real
  # steps map 1:1 to a Content entry.
  defp content_for(:welcome), do: nil
  defp content_for(:summary), do: nil
  defp content_for(step), do: Content.for(step)

  attr :step, :atom, required: true

  attr :probe, :any,
    required: true,
    doc:
      "the probe result for the current step — `Probe.Result.t() | nil`. `nil` for `:welcome` and `:summary` steps which have no probe."

  attr :probes, :list,
    required: true,
    doc:
      "list of `Probe.Result.t()` for every probed step, in step order. Used by the summary step to show the full status table."

  attr :content, :any,
    required: true,
    doc:
      "step copy — `Content.t() | nil`. `nil` for `:welcome` and `:summary` steps which render their own static content."

  attr :step_index, :integer, required: true
  attr :total, :integer, required: true

  defp step_for(%{step: :welcome} = assigns) do
    ~H"""
    <SetupSteps.welcome_step step_index={@step_index} total_steps={@total} />
    """
  end

  defp step_for(%{step: :summary} = assigns) do
    ~H"""
    <SetupSteps.summary_step
      probes={@probes}
      step_index={@step_index}
      total_steps={@total}
    />
    """
  end

  defp step_for(%{step: :watch_dirs} = assigns) do
    ~H"""
    <SetupSteps.watch_dirs_step
      result={@probe}
      content={@content}
      step_index={@step_index}
      total_steps={@total}
    />
    """
  end

  defp step_for(%{step: :mpv} = assigns) do
    ~H"""
    <SetupSteps.binary_step
      result={@probe}
      content={@content}
      binary_name="mpv"
      step_index={@step_index}
      total_steps={@total}
    />
    """
  end

  defp step_for(%{step: :ffprobe} = assigns) do
    ~H"""
    <SetupSteps.binary_step
      result={@probe}
      content={@content}
      binary_name="ffprobe"
      step_index={@step_index}
      total_steps={@total}
    />
    """
  end

  defp step_for(%{step: :tmdb} = assigns) do
    ~H"""
    <SetupSteps.integration_step
      result={@probe}
      content={@content}
      step_index={@step_index}
      total_steps={@total}
    >
      <:form>
        <form phx-submit="setup:save_integration" class="space-y-2">
          <label class="text-xs uppercase tracking-wide opacity-60">
            API key (v4 read-access token)
          </label>
          <input
            type="password"
            name="tmdb_api_key"
            placeholder="paste your TMDB v4 read-access token"
            class="input input-bordered w-full font-mono text-sm"
          />
          <.button type="submit" variant="primary" size="sm">Save</.button>
        </form>
      </:form>
    </SetupSteps.integration_step>
    """
  end

  defp step_for(%{step: :prowlarr} = assigns) do
    assigns = assign(assigns, :prowlarr_url_value, prowlarr_url())

    ~H"""
    <SetupSteps.integration_step
      result={@probe}
      content={@content}
      step_index={@step_index}
      total_steps={@total}
    >
      <:form>
        <form phx-submit="setup:save_integration" class="space-y-2">
          <label class="text-xs uppercase tracking-wide opacity-60">URL</label>
          <input
            type="text"
            name="prowlarr_url"
            value={@prowlarr_url_value}
            placeholder="http://localhost:9696"
            class="input input-bordered w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">API key</label>
          <input
            type="password"
            name="prowlarr_api_key"
            class="input input-bordered w-full font-mono text-sm"
          />
          <.button type="submit" variant="primary" size="sm">Save</.button>
        </form>
      </:form>
    </SetupSteps.integration_step>
    """
  end

  defp step_for(%{step: :download_client} = assigns) do
    assigns =
      assigns
      |> assign(:dc_type, download_client_type())
      |> assign(:dc_url, download_client_url())
      |> assign(:dc_username, download_client_username())

    ~H"""
    <SetupSteps.integration_step
      result={@probe}
      content={@content}
      step_index={@step_index}
      total_steps={@total}
    >
      <:form>
        <form phx-submit="setup:save_integration" class="space-y-2">
          <label class="text-xs uppercase tracking-wide opacity-60">Type</label>
          <input
            type="text"
            name="download_client_type"
            value={@dc_type}
            class="input input-bordered w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">URL</label>
          <input
            type="text"
            name="download_client_url"
            value={@dc_url}
            placeholder="http://localhost:8080"
            class="input input-bordered w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">Username</label>
          <input
            type="text"
            name="download_client_username"
            value={@dc_username}
            class="input input-bordered w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">Password</label>
          <input
            type="password"
            name="download_client_password"
            class="input input-bordered w-full font-mono text-sm"
          />
          <.button type="submit" variant="primary" size="sm">Save</.button>
        </form>
      </:form>
    </SetupSteps.integration_step>
    """
  end
end
