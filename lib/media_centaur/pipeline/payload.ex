defmodule MediaCentaur.Pipeline.Payload do
  @moduledoc """
  Carries all intermediate state through the pipeline stages.

  Each stage reads from and writes to this struct. The pipeline chains
  stages with `with`, and each stage returns `{:ok, payload}`,
  `{:needs_review, payload}`, or `{:error, reason}`.

  ## Fields by stage

  **Input (set by producer):**
  - `file_path` — absolute path to the video file
  - `watch_directory` — the watch directory it was detected in

  **Parse stage:**
  - `parsed` — `%Parser.Result{}` with title, year, type, season, episode

  **Search stage:**
  - `tmdb_id` — integer TMDB ID of the best match
  - `tmdb_type` — `:movie` or `:tv`
  - `confidence` — float confidence score
  - `match_title` — title of the matched TMDB result
  - `match_year` — year of the matched TMDB result
  - `match_poster_path` — poster path from TMDB
  - `candidates` — list of all scored candidates (for review)

  **FetchMetadata stage:**
  - `metadata` — structured map with entity attrs, images, identifiers

  **Ingest stage:**
  - `entity_id` — UUID of the created/found entity
  - `ingest_status` — `:new`, `:new_child`, or `:existing`

  **Import (set by Import Producer for review-resolved files):**
  - `pending_file_id` — UUID of the PendingFile being resolved
  """

  @type t :: %__MODULE__{}

  defstruct [
    # Input
    :file_path,
    :watch_directory,

    # Parse stage
    :parsed,

    # Search stage
    :tmdb_id,
    :tmdb_type,
    :confidence,
    :match_title,
    :match_year,
    :match_poster_path,
    :candidates,

    # FetchMetadata stage
    :metadata,

    # Ingest stage
    :entity_id,
    :ingest_status,

    # Import (review-resolved)
    :pending_file_id
  ]
end
