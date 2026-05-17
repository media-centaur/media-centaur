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

  alias MediaCentarr.Search.Prowlarr, as: ProwlarrClient
  alias MediaCentarr.Downloads.DownloadClient.QBittorrent
  alias MediaCentarr.Config
  alias MediaCentarr.IntegrationHealth
  alias MediaCentarr.Secret
  alias MediaCentarr.Setup.Gate
  alias MediaCentarrWeb.Components.SetupSteps
  alias MediaCentarrWeb.Live.SetupLive.{Content, Probes}

  # Tour steps in order. `:welcome` and `:summary` are wrapper steps
  # owned by this LiveView (no probe). The middle slice is sourced from
  # `Probes.step_order/0` so the probe-list and step-list stay in sync.
  @step_order [:welcome] ++ Probes.step_order() ++ [:summary]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: IntegrationHealth.subscribe()

    {:ok,
     assign(socket,
       current_step: hd(@step_order),
       probes: [],
       integration_health: IntegrationHealth.all_statuses()
     )}
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
    step = socket.assigns.current_step
    probe = current_probe(socket.assigns.probes, step)
    health = Map.get(socket.assigns.integration_health, step)

    case Gate.check(step, probe, health) do
      :ok ->
        case advance(step, +1) do
          :finish -> finish(socket)
          next_step -> {:noreply, push_patch(socket, to: step_path(next_step))}
        end

      {:blocked, reason} ->
        {:noreply, put_flash(socket, :error, Gate.reason_message(reason))}
    end
  end

  def handle_event("setup:back", _params, socket) do
    case advance(socket.assigns.current_step, -1) do
      :finish -> {:noreply, socket}
      step -> {:noreply, push_patch(socket, to: step_path(step))}
    end
  end

  # Skip is the gate's escape hatch: explicit user intent to bypass an
  # incomplete step. Unlike Next, it never consults `Gate.check/3` —
  # otherwise an optional integration with no credentials would trap the
  # user (Next blocked, Skip blocked).
  def handle_event("setup:skip", _params, socket) do
    case advance(socket.assigns.current_step, +1) do
      :finish -> finish(socket)
      step -> {:noreply, push_patch(socket, to: step_path(step))}
    end
  end

  # ---------------------------------------------------------------------------
  # Save-path event (binary steps — mpv / ffprobe)
  #
  # Binary steps have no async network test — the probe is synchronous
  # (does the file exist + is it executable?). So after saving, we
  # re-run probes and immediately consult the gate; if probe is `:ok`
  # the step is satisfied and the user advances.
  # ---------------------------------------------------------------------------

  def handle_event("setup:save_path", %{"id" => id, "path" => path}, socket) do
    save_binary_path(id, path)
    socket = refresh_probes(socket)
    {:noreply, maybe_advance_after_save(socket)}
  end

  def handle_event("setup:save_path", %{"path" => path} = params, socket) do
    id = params["id"] || Atom.to_string(socket.assigns.current_step)
    save_binary_path(id, path)
    socket = refresh_probes(socket)
    {:noreply, maybe_advance_after_save(socket)}
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
    # Save every recognised field; track whether ANY actually mutated
    # config. The empty-submit case (user revisits an already-saved step
    # and clicks Next without re-entering creds) leaves `changed?` false
    # and skips the verify, so the gate just advances on the existing
    # `:ok` health state instead of re-running the network test.
    changed? =
      Enum.reduce(params, false, fn
        {"_" <> _, _}, acc -> acc
        {key, value}, acc when is_binary(key) -> save_integration_field(key, value) or acc
        _, acc -> acc
      end)

    ProwlarrClient.invalidate_client()
    QBittorrent.invalidate_client()
    MediaCentarr.TMDB.Client.invalidate_client()

    socket = refresh_probes(socket)

    id = integration_atom(params["_integration"])

    # Kick a fresh verify only when config actually changed AND the step
    # is a known integration. This is the single explicit verify trigger
    # — IntegrationHealth no longer auto-kicks on each `:config_updated`
    # broadcast, which avoided a per-field race where (e.g.) saving
    # `prowlarr_api_key` before `prowlarr_url` fired a verify against
    # stale URL and got stuck at `:error` until the user clicked Next
    # again. See `IntegrationHealth.handle_info({:config_updated, ...})`.
    if changed? and id, do: IntegrationHealth.verify(id)

    step = socket.assigns.current_step
    probe = current_probe(socket.assigns.probes, step)
    health = Map.get(socket.assigns.integration_health, step)

    case Gate.check(step, probe, health) do
      :ok ->
        case advance(step, +1) do
          :finish -> finish(socket)
          next_step -> {:noreply, push_patch(socket, to: step_path(next_step))}
        end

      {:blocked, _reason} ->
        # Stay on the step. For TMDB (gating step) the user sees a
        # transient "Verifying…" until the PubSub auto-advance fires
        # when the verify completes.
        flash =
          cond do
            is_nil(id) -> "Saved."
            changed? -> "Saved. Verifying #{id}…"
            true -> "This step is already configured."
          end

        {:noreply, put_flash(socket, :info, flash)}
    end
  end

  # ---------------------------------------------------------------------------
  # Test connection
  # ---------------------------------------------------------------------------

  def handle_event("setup:test_connection", %{"id" => id}, socket) do
    case integration_atom(id) do
      nil ->
        {:noreply, socket}

      atom ->
        IntegrationHealth.verify(atom)
        {:noreply, put_flash(socket, :info, "Verifying #{id}…")}
    end
  end

  @impl true
  def handle_info({:integration_health_changed, %IntegrationHealth.Status{} = status}, socket) do
    socket =
      socket
      |> assign(integration_health: Map.put(socket.assigns.integration_health, status.id, status))
      |> flash_for_health_change(status)
      |> maybe_auto_advance(status)

    {:noreply, socket}
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
    # Land on /library, not /, so the user sees the empty-state scan
    # button + ingest indicator (LibraryLive.handle_info(:tick_pipeline))
    # while the pipeline finishes processing the files the watcher just
    # dispatched. Home would show "no continue watching" with no signal
    # that anything is happening.
    {:noreply, push_navigate(socket, to: "/library")}
  end

  defp step_index(step), do: Enum.find_index(@step_order, &(&1 == step)) + 1

  defp current_probe(probes, step), do: Enum.find(probes, &(&1.id == step))

  defp save_binary_path("mpv", path), do: Config.update(:mpv_path, path)
  defp save_binary_path("ffprobe", path), do: Config.update(:ffprobe_path, path)
  defp save_binary_path(_, _), do: :ok

  # Returns `true` when the call actually mutated Config, `false`
  # otherwise (empty value, unknown key). The caller folds these into a
  # `changed?` flag that drives the verify decision.
  defp save_integration_field("tmdb_api_key", ""), do: false
  defp save_integration_field("tmdb_api_key", value), do: update_if_changed(:tmdb_api_key, value)
  defp save_integration_field("prowlarr_url", value), do: update_if_changed(:prowlarr_url, value)
  defp save_integration_field("prowlarr_api_key", ""), do: false

  defp save_integration_field("prowlarr_api_key", value), do: update_if_changed(:prowlarr_api_key, value)

  defp save_integration_field("download_client_type", value),
    do: update_if_changed(:download_client_type, value)

  defp save_integration_field("download_client_url", value),
    do: update_if_changed(:download_client_url, value)

  defp save_integration_field("download_client_username", value),
    do: update_if_changed(:download_client_username, value)

  defp save_integration_field("download_client_password", ""), do: false

  defp save_integration_field("download_client_password", value),
    do: update_if_changed(:download_client_password, value)

  defp save_integration_field(_, _), do: false

  defp update_if_changed(key, value) do
    if Config.get(key) == value do
      false
    else
      Config.update(key, value)
      true
    end
  end

  # Map the string id used on the wire (`name="_integration"` hidden
  # field, `phx-value-id="..."`, etc.) to the atom IntegrationHealth uses
  # internally. Falls back to nil for unrecognised values so the caller
  # branches cleanly.
  defp integration_atom("tmdb"), do: :tmdb
  defp integration_atom("prowlarr"), do: :prowlarr
  defp integration_atom("download_client"), do: :download_client
  defp integration_atom(_), do: nil

  # PubSub-driven flash on health transitions. Only fire for terminal
  # states — :pending is a transient that the UI shows as a spinner, not
  # a banner.
  defp flash_for_health_change(socket, %IntegrationHealth.Status{id: id, test_state: :ok}) do
    put_flash(socket, :info, "#{id}: connection verified ✓")
  end

  defp flash_for_health_change(socket, %IntegrationHealth.Status{id: id, test_state: :error}) do
    put_flash(socket, :error, "#{id}: connection test failed — check the credentials")
  end

  defp flash_for_health_change(socket, _status), do: socket

  # Auto-advance only when the user is still parked on the step whose
  # health just went `:ok`. If they've already navigated forward (or
  # back), the async result lands quietly without yanking them around.
  defp maybe_auto_advance(socket, %IntegrationHealth.Status{id: id, test_state: :ok}) do
    if socket.assigns.current_step == id do
      case advance(id, +1) do
        :finish ->
          {:noreply, socket} = finish(socket)
          socket

        step ->
          push_patch(socket, to: step_path(step))
      end
    else
      socket
    end
  end

  defp maybe_auto_advance(socket, _status), do: socket

  # After a synchronous save (binary steps), if the freshly-probed step
  # satisfies the gate, advance — otherwise stay and let the user see the
  # status callout / re-check. No flash on stay: the callout above the
  # form already carries the explanation.
  defp maybe_advance_after_save(socket) do
    step = socket.assigns.current_step
    probe = current_probe(socket.assigns.probes, step)
    health = Map.get(socket.assigns.integration_health, step)

    case Gate.check(step, probe, health) do
      :ok ->
        case advance(step, +1) do
          :finish ->
            {:noreply, socket} = finish(socket)
            socket

          next_step ->
            push_patch(socket, to: step_path(next_step))
        end

      {:blocked, _reason} ->
        socket
    end
  end

  # The default URLs match the standard local-install endpoints. We
  # pre-fill them so the user doesn't have to type a value almost every
  # install will want — but the placeholder stays on the input so if
  # the user clears it the hint is still visible.
  @prowlarr_default_url "http://localhost:9696"
  @download_client_default_url "http://localhost:8080"

  defp prowlarr_url, do: Config.get(:prowlarr_url) || @prowlarr_default_url

  defp download_client_url, do: Config.get(:download_client_url) || @download_client_default_url

  defp download_client_username, do: Config.get(:download_client_username) || ""

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    step_index = step_index(assigns.current_step)
    total = length(@step_order)
    probe = current_probe(assigns.probes, assigns.current_step)
    health = Map.get(assigns.integration_health, assigns.current_step)
    blocked? = Gate.check(assigns.current_step, probe, health) != :ok

    assigns =
      assigns
      |> assign(:probe, probe)
      |> assign(:content, content_for(assigns.current_step))
      |> assign(:step_index, step_index)
      |> assign(:total, total)
      |> assign(:blocked?, blocked?)

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
        blocked?={@blocked?}
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

  attr :blocked?, :boolean,
    required: true,
    doc:
      "Whether `Setup.Gate.check/3` currently blocks advancement. Propagated to step components so the Next button can be visually disabled on non-form steps."

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
      blocked?={@blocked?}
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
      optional?={true}
      blocked?={@blocked?}
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
      optional?={true}
      blocked?={@blocked?}
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
      form_id="setup-step-tmdb-form"
      optional?={false}
      blocked?={@blocked?}
    >
      <:form>
        <form
          id="setup-step-tmdb-form"
          phx-submit="setup:save_integration"
          class="space-y-2"
        >
          <input type="hidden" name="_integration" value="tmdb" />
          <p class="text-sm opacity-80">
            TMDB API access is <strong>free</strong>. Create an account at
            <.link
              href="https://www.themoviedb.org/signup"
              target="_blank"
              rel="noopener"
              class="link link-primary"
            >
              themoviedb.org
            </.link>
            and copy your v4 read-access token from <.link
              href="https://www.themoviedb.org/settings/api"
              target="_blank"
              rel="noopener"
              class="link link-primary"
            >Settings → API</.link>.
          </p>
          <label class="text-xs uppercase tracking-wide opacity-60 block">
            API key (v4 read-access token)
          </label>
          <input
            type="password"
            name="tmdb_api_key"
            placeholder="paste your TMDB v4 read-access token"
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
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
      form_id="setup-step-prowlarr-form"
      optional?={true}
      blocked?={@blocked?}
    >
      <:form>
        <form
          id="setup-step-prowlarr-form"
          phx-submit="setup:save_integration"
          class="space-y-2"
        >
          <input type="hidden" name="_integration" value="prowlarr" />
          <label class="text-xs uppercase tracking-wide opacity-60 block">URL</label>
          <input
            type="text"
            name="prowlarr_url"
            value={@prowlarr_url_value}
            placeholder="http://localhost:9696"
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">API key</label>
          <input
            type="password"
            name="prowlarr_api_key"
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
        </form>
      </:form>
    </SetupSteps.integration_step>
    """
  end

  defp step_for(%{step: :download_client} = assigns) do
    assigns =
      assigns
      |> assign(:dc_url, download_client_url())
      |> assign(:dc_username, download_client_username())

    ~H"""
    <SetupSteps.integration_step
      result={@probe}
      content={@content}
      step_index={@step_index}
      total_steps={@total}
      form_id="setup-step-download-client-form"
      optional?={true}
      blocked?={@blocked?}
    >
      <:form>
        <form
          id="setup-step-download-client-form"
          phx-submit="setup:save_integration"
          class="space-y-2"
        >
          <input type="hidden" name="_integration" value="download_client" />
          <label class="text-xs uppercase tracking-wide opacity-60 block">Type</label>
          <select
            name="download_client_type"
            class="select select-bordered select-sm w-full font-mono text-sm"
          >
            <option value="qbittorrent" selected>qBittorrent</option>
          </select>
          <p class="text-xs opacity-70 mt-1">
            qBittorrent is currently the only supported download client.
          </p>
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">URL</label>
          <input
            type="text"
            name="download_client_url"
            value={@dc_url}
            placeholder="http://localhost:8080"
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">Username</label>
          <input
            type="text"
            name="download_client_username"
            value={@dc_username}
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
          <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">Password</label>
          <input
            type="password"
            name="download_client_password"
            class="input input-bordered input-sm w-full font-mono text-sm"
          />
        </form>
      </:form>
    </SetupSteps.integration_step>
    """
  end
end
