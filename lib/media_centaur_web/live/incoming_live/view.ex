defmodule MediaCentaurWeb.IncomingLive.View do
  @moduledoc """
  The Downloads page's one composition point (ADR-030 applied at page
  scale): the operational sections — the draft plans and the pursuits in
  flight — built together from injected facts by one pure function, so
  the LiveView holds a single `%View{}` assign.

  Honest degradation is enforced here and only here: without an indexer
  (`prowlarr_ready?` false) the operational sections come back empty,
  whatever the caller passes. Templates never re-check capabilities.

  Deliberately NOT composed here: live queue pairing. `QueueMatcher.match/2`
  runs at render time (see the render-time pairing note in the page module)
  so the DB-backed sections don't rebuild on every queue snapshot.
  """

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaurWeb.IncomingLive.View

  defstruct in_flight: [], drafts: []

  @type t :: %View{in_flight: [PursuitRow.t()], drafts: [map()]}

  @doc """
  Build the page view from already-read facts: `:pursuit_rows` and
  `:drafts`, the acquisition reads (the History archive reads separately
  via `compute_history_rows`), and `:prowlarr_ready?`, the gate.
  """
  @spec build(map()) :: t()
  def build(inputs) do
    %View{
      in_flight: if(inputs.prowlarr_ready?, do: inputs.pursuit_rows, else: []),
      drafts: if(inputs.prowlarr_ready?, do: inputs.drafts, else: [])
    }
  end
end
