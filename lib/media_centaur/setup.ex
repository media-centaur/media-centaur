defmodule MediaCentaur.Setup do
  @moduledoc """
  Setup Tour bounded context — owns the advance-gate logic that decides
  when the wizard may move past a step.

  The state itself (integration health, media-dir presence) lives in
  other contexts (`IntegrationHealth`, `Watcher`, etc.). This context
  composes those into a single yes-or-no answer for the wizard UI.
  """
  use Boundary,
    deps: [MediaCentaur.IntegrationHealth],
    exports: [Gate]
end
