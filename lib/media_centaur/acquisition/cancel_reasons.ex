defmodule MediaCentaur.Acquisition.CancelReasons do
  @moduledoc """
  The closed set of strings stored in `acquisition_targets.cancelled_reason`
  and surfaced in pursuit timeline events.

  Inline string literals at call sites drift — different pages have used
  different reasons for the same action ("user_disabled" vs "user_request"
  for a manual cancel). This module is the single source of truth.

  Every constant below names its write site, and
  `CancelReasonsTest` asserts the set covers each one. That guard is the
  point: between the ADR-056 cutover and 2026-09-17 this module described the
  retired seeker's vocabulary while the Pursuits commands wrote their own
  literals, and nothing noticed — the declared set and the stored set had no
  value in common.

  | constant                 | written by                                      |
  |--------------------------|-------------------------------------------------|
  | `user_request`           | `IncomingLive` — user cancelled the pursuit      |
  | `item_removed`           | `Reactor` — item untracked from release tracking |
  | `auto_grab_disabled`     | `ModeReconciler` — auto-grab switched off        |
  | `pursuit_cancelled`      | `Commands.Cancel` — in-flight targets closed     |
  | `pursuit_satisfied`      | `Commands.Satisfy` — losing targets closed       |
  | `replaced_by_pick`       | `Commands.PickTarget` — user picked another      |
  | `replaced_by_user_pivot` | `Commands.ChangeTarget` — user pivoted           |
  | `orphan_target`          | `Jobs.PursueTarget` — no owning pursuit          |
  | `exhausted`              | `Jobs.PursueTarget` — attempt budget spent       |
  | `download_failed`        | `Commands.AutoCancel` — `Policy` rule 3          |
  | `zero_seeders`           | `Commands.AutoCancel` — `Policy` rule 4          |

  **Historical values.** Rows written before 2026-09-17 may carry reasons no
  longer declared here — `superseded_by_plans` (legacy seeker, system-cancelled
  at the ADR-056 cutover) and `user_cancelled` (showcase seed data). They are
  deliberately absent: nothing can write them again. `TimelineEntry`
  underscore-strips any unrecognised reason, so old rows still read cleanly.
  """

  @user_request "user_request"
  @item_removed "item_removed"
  @auto_grab_disabled "auto_grab_disabled"
  @pursuit_cancelled "pursuit_cancelled"
  @pursuit_satisfied "pursuit_satisfied"
  @replaced_by_pick "replaced_by_pick"
  @replaced_by_user_pivot "replaced_by_user_pivot"
  @orphan_target "orphan_target"
  @exhausted "exhausted"
  @download_failed "download_failed"
  @zero_seeders "zero_seeders"

  @all [
    @user_request,
    @item_removed,
    @auto_grab_disabled,
    @pursuit_cancelled,
    @pursuit_satisfied,
    @replaced_by_pick,
    @replaced_by_user_pivot,
    @orphan_target,
    @exhausted,
    @download_failed,
    @zero_seeders
  ]

  @type t :: String.t()

  @spec user_request() :: t()
  def user_request, do: @user_request

  @spec item_removed() :: t()
  def item_removed, do: @item_removed

  @spec auto_grab_disabled() :: t()
  def auto_grab_disabled, do: @auto_grab_disabled

  @spec pursuit_cancelled() :: t()
  def pursuit_cancelled, do: @pursuit_cancelled

  @spec pursuit_satisfied() :: t()
  def pursuit_satisfied, do: @pursuit_satisfied

  @spec replaced_by_pick() :: t()
  def replaced_by_pick, do: @replaced_by_pick

  @spec replaced_by_user_pivot() :: t()
  def replaced_by_user_pivot, do: @replaced_by_user_pivot

  @spec orphan_target() :: t()
  def orphan_target, do: @orphan_target

  @spec exhausted() :: t()
  def exhausted, do: @exhausted

  @spec download_failed() :: t()
  def download_failed, do: @download_failed

  @spec zero_seeders() :: t()
  def zero_seeders, do: @zero_seeders

  @doc """
  The stored reason for a `Pursuits.Policy` auto-cancel decision.

  `Policy` decides in atoms and this column stores strings. Mapping them
  here — rather than `Atom.to_string/1` at the write site — is what keeps a
  new `Policy` decision from silently minting a reason outside this set.
  """
  @spec from_policy(:download_failed | :zero_seeders) :: t()
  def from_policy(:download_failed), do: @download_failed
  def from_policy(:zero_seeders), do: @zero_seeders

  # `all/0` and `valid?/1` have no production caller and are kept deliberately:
  # they are the surface `CancelReasonsTest` asserts the vocabulary through,
  # and that test is the only thing that would have caught this module
  # describing a set the database never held. Deleting them would remove the
  # guard, not dead weight.

  @doc "Returns every recognised cancel reason string."
  @spec all() :: [t()]
  def all, do: @all

  @doc "True when `value` is one of the recognised reasons."
  @spec valid?(term()) :: boolean()
  def valid?(value), do: value in @all
end
