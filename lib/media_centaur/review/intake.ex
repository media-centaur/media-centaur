defmodule MediaCentaur.Review.Intake do
  @moduledoc """
  Reacts to the `"review:intake"` topic — the pipeline and the rematch
  flow handing files to Review — by calling the matching `Review`
  function:

  - `{:needs_review, attrs}` → `Review.add_pending_file/1`
  - `{:review_completed, id}` → `Review.complete_review/1`
  - `{:files_for_review, files}` → `Review.add_files_for_review/1`
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Review
  alias MediaCentaur.Topics

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Topics.subscribe(Topics.review_intake())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:needs_review, attrs}, state) do
    case Review.add_pending_file(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> Log.warning(:review, "failed to create pending file — #{inspect(reason)}")
    end

    {:noreply, state}
  end

  def handle_info({:review_completed, pending_file_id}, state) do
    Review.complete_review(pending_file_id)
    {:noreply, state}
  end

  def handle_info({:files_for_review, files}, state) do
    Review.add_files_for_review(files)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
