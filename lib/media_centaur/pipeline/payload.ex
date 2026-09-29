defmodule MediaCentaur.Pipeline.Payload do
  @moduledoc """
  Carries all intermediate state through the pipeline stages.

  Each stage reads from and writes to this struct. The pipeline chains
  stages with `with`, and each stage returns `{:ok, payload}`,
  `{:needs_review, payload}`, or `{:error, reason}`.

  ## Fields by stage

  **Input (set by producer):**
  - `file_path` — absolute path to the video file
  - `media_directory` — the media directory it was detected in
  - `match_season`, `match_episode` — Import only: the season and episode
    the match places the file at (`nil` for a movie). They come with the
    match, from the parse for a Discovery match and from the review item
    for an approval, and Import uses them instead of reading the path
    again — so a reviewer's choice reaches the library.

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

  **Discovery outcome (set by `Discovery.process/1`):**
  - `discovery_status` — `:matched` or `:needs_review`. The Discovery
    batcher broadcasts only `:matched` payloads for import; a
    `:needs_review` payload still carries `tmdb_id`/`confidence` (the
    review UI shows the best candidate), so field presence cannot
    distinguish the two outcomes.

  **FetchMetadata stage:**
  - `metadata` — structured map with entity attrs, images, identifiers

  **Ingest stage:**
  - `entity_id` — UUID of the created/found entity
  - `ingest_status` — `:new`, `:new_child`, or `:existing`
  - `pending_images` — list of image maps to queue for download
  """

  @type t :: %__MODULE__{}

  defstruct [
    # Input
    :file_path,
    :media_directory,
    :match_season,
    :match_episode,

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

    # Discovery outcome
    :discovery_status,

    # FetchMetadata stage
    :metadata,

    # Ingest stage
    :entity_id,
    :ingest_status,
    :pending_images
  ]
end
