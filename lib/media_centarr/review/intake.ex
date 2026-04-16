defmodule MediaCentarr.Review.Intake do
  @moduledoc """
  Subscribes to `"review:intake"` and manages PendingFile lifecycle.

  Handles three event types:

  - `{:needs_review, attrs}` — creates a PendingFile for human review
  - `{:review_completed, id}` — destroys a PendingFile after import finishes
  - `{:files_for_review, files}` — creates PendingFiles from a rematch (files
    are parsed to extract metadata)
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Parser
  alias MediaCentarr.Review
  alias MediaCentarr.Topics

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.review_intake())
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
        MediaCentarr.PubSub,
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
          MediaCentarr.PubSub,
          Topics.review_updates(),
          {:file_reviewed, pending_file_id}
        )

      {:error, :not_found} ->
        :ok
    end

    :ok
  end

  @doc """
  Creates PendingFiles from a list of file maps (from a rematch).

  Each file map has `:file_path` and `:watch_dir`. The file path is parsed
  to extract metadata, then a PendingFile is created and broadcast.

  Returns `{:ok, count}` with the number of PendingFiles created.
  """
  @spec receive_files_for_review([map()]) :: {:ok, non_neg_integer()}
  def receive_files_for_review(files) do
    pending_files =
      Enum.map(files, fn file ->
        attrs = build_pending_attrs(file)

        case create_pending_file(attrs) do
          {:ok, pending_file} ->
            pending_file

          {:error, reason} ->
            Log.warning(
              :library,
              "failed to create pending file for rematch — #{inspect(reason)}"
            )

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    Log.info(:library, "rematch — created #{length(pending_files)} pending files")

    {:ok, length(pending_files)}
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

  @impl true
  def handle_info({:files_for_review, files}, state) do
    receive_files_for_review(files)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private — file path parsing for rematch
  # ---------------------------------------------------------------------------

  defp build_pending_attrs(file) do
    parsed = Parser.parse(file.file_path)
    {search_title, search_year} = search_params(parsed)

    %{
      file_path: file.file_path,
      watch_directory: file.watch_dir,
      parsed_title: search_title,
      parsed_year: search_year,
      parsed_type: type_to_string(parsed.type),
      season_number: parsed.season,
      episode_number: parsed.episode
    }
  end

  defp search_params(%{type: :extra, parent_title: title, parent_year: year}), do: {title, year}
  defp search_params(%{title: title, year: year}), do: {title, year}

  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)
end
