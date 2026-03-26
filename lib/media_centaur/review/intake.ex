defmodule MediaCentaur.Review.Intake do
  @moduledoc """
  Subscribes to `"review:intake"` and manages PendingFile lifecycle.

  Handles two event types:

  - `{:needs_review, attrs}` — creates a PendingFile for human review
  - `{:review_completed, id}` — destroys a PendingFile after import finishes
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
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.review_intake())
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a PendingFile from a plain map of pre-normalized attributes.

  Uses find_or_create for idempotency — a second call with the same file_path
  returns the existing record. Broadcasts `{:file_added, id}` to
  `"review:updates"` on success.
  """
  @spec create_pending_file(map()) :: {:ok, struct()} | {:error, term()}
  def create_pending_file(attrs) do
    with {:ok, pending_file} <- Review.find_or_create_pending_file(attrs) do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.review_updates(),
        {:file_added, pending_file.id}
      )

      {:ok, pending_file}
    end
  end

  @doc """
  Destroys a PendingFile by ID and broadcasts `{:file_reviewed, id}` to
  `"review:updates"`. Returns `:ok` even if the record was already removed.
  """
  @spec complete_review(Ecto.UUID.t()) :: :ok
  def complete_review(pending_file_id) do
    case Review.get_pending_file(pending_file_id) do
      {:ok, pending_file} ->
        Review.destroy_pending_file!(pending_file)

        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          Topics.review_updates(),
          {:file_reviewed, pending_file_id}
        )

      {:error, :not_found} ->
        :ok
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:needs_review, attrs}, state) do
    case create_pending_file(attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Log.warning(:library, "failed to create pending file — #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:review_completed, pending_file_id}, state) do
    complete_review(pending_file_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
