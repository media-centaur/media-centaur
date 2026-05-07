defmodule MediaCentarr.Acquisition.ViewModels.TimelineEntry do
  @moduledoc "Display contract for one event in the timeline."

  @enforce_keys [:kind, :occurred_at, :summary, :severity]
  defstruct [:kind, :occurred_at, :summary, :severity, :detail]

  @type severity :: :info | :success | :warning | :error
  @type t :: %__MODULE__{
          kind: String.t(),
          occurred_at: DateTime.t(),
          summary: String.t(),
          severity: severity(),
          detail: String.t() | nil
        }
end
