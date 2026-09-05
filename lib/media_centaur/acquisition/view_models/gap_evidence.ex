defmodule MediaCentaur.Acquisition.ViewModels.GapEvidence do
  @moduledoc """
  The durable evidence behind a plan's gap verdict (UIDR-022): which
  ladder searches have corpus records, what they returned, and — for
  movie plans — every raw candidate with the reason the run rejected
  it. Built by `Plans.Alternatives.gap_evidence/1` from the search corpus, never
  from the transient activity ticker, so a re-opened board shows the
  same evidence days later. Cleanup rides corpus retention.
  """

  defmodule Search do
    @moduledoc "One ladder term's corpus record: when it last ran and what it returned."

    @enforce_keys [:term, :searched_at, :result_count]
    defstruct [:term, :searched_at, :result_count]

    @type t :: %__MODULE__{
            term: String.t(),
            searched_at: DateTime.t(),
            result_count: non_neg_integer()
          }
  end

  defmodule Rejected do
    @moduledoc """
    One raw candidate the run rejected, with the first gate it failed —
    the same gate order the run applies (`:red_flag`, then `:excluded`,
    then `:identity`).
    """

    @enforce_keys [:guid, :title, :reason]
    defstruct [:guid, :title, :reason, :quality, :seeders, :size_bytes]

    @type reason :: :red_flag | :excluded | :identity

    @type t :: %__MODULE__{
            guid: String.t(),
            title: String.t(),
            reason: reason(),
            quality: String.t() | nil,
            seeders: integer() | nil,
            size_bytes: integer() | nil
          }
  end

  @enforce_keys [:searches, :rejected, :raw_total, :checked_at]
  defstruct [:searches, :rejected, :raw_total, :checked_at]

  @typedoc """
  - `searches` — the plan's gap-surface ladder terms that have a corpus
    record, in ladder order. Terms never searched (or pruned past
    retention) are absent.
  - `rejected` — classified raw candidates, deduped by guid. Movie
    plans only; TV stays aggregate (`raw_total`).
  - `raw_total` — unique raw candidates across the searched terms.
  - `checked_at` — the newest `searched_at`; nil when nothing ran.
  """
  @type t :: %__MODULE__{
          searches: [Search.t()],
          rejected: [Rejected.t()],
          raw_total: non_neg_integer(),
          checked_at: DateTime.t() | nil
        }
end
