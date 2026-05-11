defmodule MediaCentarrWeb.PursuitLive do
  @moduledoc """
  Detail page for a single pursuit at `/download/:pursuit_id`.

  Subscribes to `acquisition:updates` and `acquisition:queue` so the
  status panel refreshes on both pursuit events and queue snapshots.
  Every refresh recomputes via `Pursuits.status_for/1`.
  """

  use MediaCentarrWeb, :live_view

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition
  alias MediaCentarr.Acquisition.{CancelReasons, Pursuits}
  alias MediaCentarr.Acquisition.Pursuits.Pursuit

  alias MediaCentarr.Acquisition.Pursuits.Commands.{
    Cancel,
    RecordUserChoice,
    ReSearch,
    RequestDecision
  }

  alias MediaCentarr.Acquisition.Pursuits.Events, as: PursuitEvents
  alias MediaCentarr.Acquisition.ViewModels
  alias MediaCentarr.Acquisition.ViewModels.Alternative
  alias MediaCentarrWeb.Components.Acquisition.DecisionCard, as: DecisionCardComponent

  alias MediaCentarrWeb.Components.Acquisition.{
    PursuitActivity,
    PursuitHeader,
    PursuitTimeline
  }

  alias MediaCentarrWeb.Layouts

  @decision_prompt "Pick an alternative release."

  @impl true
  def mount(%{"pursuit_id" => id}, _session, socket) do
    if connected?(socket) do
      Acquisition.subscribe()
      Acquisition.subscribe_queue()
    end

    socket =
      socket
      |> assign(pursuit_id: id)
      |> load_state()

    {:ok, socket}
  end

  @impl true
  def render(%{not_found?: true} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/download" acquisition_ready={@acquisition_ready}>
      <div class="max-w-2xl mx-auto py-8 text-center text-base-content/60">
        Pursuit not found.
        <.link navigate="/download" class="link link-primary ml-2">Back to Downloads</.link>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/download" acquisition_ready={@acquisition_ready}>
      <div class="max-w-2xl mx-auto space-y-4 py-6">
        <div>
          <.link navigate="/download" class="text-xs text-base-content/60 hover:text-base-content">
            ← Back to Downloads
          </.link>
        </div>

        <PursuitHeader.pursuit_header vm={@header} />

        <PursuitActivity.pursuit_activity
          vm={@status}
          on_cancel="cancel_pursuit"
          on_re_search="re_search"
          on_request_decision="request_decision"
        />

        <DecisionCardComponent.decision_card :if={@decision_card} vm={@decision_card} />

        <PursuitTimeline.timeline vm={@timeline} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("cancel_pursuit", _params, socket) do
    case Cancel.execute(%{
           pursuit_id: socket.assigns.pursuit_id,
           cancelled_by: :user,
           reason: CancelReasons.user_request()
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pursuit cancelled.") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit cancel failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not cancel pursuit.")}
    end
  end

  def handle_event("re_search", _params, socket) do
    case ReSearch.execute(%{pursuit_id: socket.assigns.pursuit_id}) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Re-searching now…") |> load_state()}

      {:error, :not_eligible} ->
        {:noreply, put_flash(socket, :error, "This pursuit can't be re-searched right now.")}

      {:error, reason} ->
        Log.warning(:acquisition, "pursuit re-search failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not re-search this pursuit.")}
    end
  end

  def handle_event("request_decision", _params, socket) do
    case RequestDecision.execute(%{
           pursuit_id: socket.assigns.pursuit_id,
           prompt: @decision_prompt
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Pick a release below.") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "request decision failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not switch to decision mode.")}
    end
  end

  def handle_event(
        "pick_alternative",
        %{"pursuit-id" => pursuit_id, "guid" => guid, "label" => label},
        socket
      ) do
    case RecordUserChoice.execute(%{
           pursuit_id: pursuit_id,
           chosen_guid: guid,
           choice_label: label
         }) do
      {:ok, _pursuit} ->
        {:noreply, socket |> put_flash(:info, "Trying alternative…") |> load_state()}

      {:error, reason} ->
        Log.warning(:acquisition, "record user choice failed — #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not pick that alternative.")}
    end
  end

  @impl true
  def handle_info({:queue_state, _queue}, socket), do: {:noreply, load_state(socket)}

  def handle_info(%struct{pursuit_id: pid}, %{assigns: %{pursuit_id: pid}} = socket) do
    if PursuitEvents.event?(struct) do
      {:noreply, load_state(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- private ---------------------------------------------------------------

  defp load_state(socket) do
    case Pursuits.get(socket.assigns.pursuit_id) do
      {:ok, %Pursuit{} = pursuit} ->
        {:ok, header} = Pursuits.header_for(pursuit.id)
        {:ok, status} = Pursuits.status_for(pursuit.id)
        timeline = Pursuits.timeline_for(pursuit.id)
        decision_card = build_decision_card(pursuit)

        socket
        |> assign(:pursuit, pursuit)
        |> assign(:header, header)
        |> assign(:status, status)
        |> assign(:timeline, timeline)
        |> assign(:decision_card, decision_card)
        |> assign(:not_found?, false)

      {:error, :not_found} ->
        assign(socket, :not_found?, true)
    end
  end

  defp build_decision_card(%Pursuit{state: "needs_decision"} = pursuit) do
    %ViewModels.DecisionCard{
      pursuit_id: pursuit.id,
      prompt: @decision_prompt,
      alternatives: fetch_alternatives(pursuit),
      loading?: false
    }
  end

  defp build_decision_card(_pursuit), do: nil

  defp fetch_alternatives(%Pursuit{} = pursuit) do
    opts =
      []
      |> put_when_present(:type, search_type_for(pursuit.tmdb_type))
      |> put_when_present(:year, pursuit.year)

    case Acquisition.search(pursuit.title, opts) do
      {:ok, results} ->
        excluded = MapSet.new(pursuit.tried_release_guids)

        results
        |> Enum.reject(fn r -> MapSet.member?(excluded, r.guid) end)
        |> Enum.take(8)
        |> Enum.map(&search_result_to_alternative/1)

      {:error, _reason} ->
        []
    end
  end

  defp search_type_for("tv"), do: :tv
  defp search_type_for("movie"), do: :movie
  defp search_type_for(_), do: nil

  defp put_when_present(opts, _key, nil), do: opts
  defp put_when_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp search_result_to_alternative(result) do
    %Alternative{
      guid: result.guid,
      title: result.title,
      indexer: indexer_name(result),
      quality: quality_label(result),
      size_bytes: Map.get(result, :size_bytes),
      seeders: Map.get(result, :seeders),
      indexer_id: Map.get(result, :indexer_id)
    }
  end

  defp indexer_name(%{indexer: indexer}) when is_binary(indexer), do: indexer
  defp indexer_name(_), do: "Unknown"

  defp quality_label(%{quality: q}) when is_atom(q), do: MediaCentarr.Acquisition.Quality.label(q)
  defp quality_label(_), do: nil
end
