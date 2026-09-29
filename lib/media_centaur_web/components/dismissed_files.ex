defmodule MediaCentaurWeb.Components.DismissedFiles do
  @moduledoc """
  The dismissed files of a review queue, behind a disclosure, each with
  Restore — the one way to undo a dismissal from the page. Rendered by
  both review surfaces, Identity (`ReviewLive`) and Episode mapping
  (`EpisodeMappingLive`); the host answers the `event` with the file's id.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Disclosure, only: [disclosure: 1]

  attr :id, :string, required: true, doc: "the disclosure's id, its key in the page's `DisclosureState`."
  attr :open, :boolean, required: true

  attr :files, :list,
    required: true,
    doc: "`%{id, path}` per dismissed file, `path` relative to its media directory."

  attr :hint, :string, required: true, doc: "one line on what restoring does on this surface."
  attr :event, :string, default: "restore", doc: "pushed with `phx-value-id` by a file's Restore."
  attr :class, :any, default: nil, doc: "the group's own spacing."

  def dismissed_files(assigns) do
    ~H"""
    <.disclosure
      :if={@files != []}
      id={@id}
      open={@open}
      label={"Dismissed (#{length(@files)})"}
      class={@class}
    >
      <p class="text-xs text-base-content/55 mb-2">{@hint}</p>
      <ul class="space-y-1">
        <li :for={file <- @files} id={"#{@id}-#{file.id}"} class="flex items-center gap-2">
          <span
            class="flex-1 min-w-0 font-mono text-xs text-base-content/70 truncate-left"
            title={file.path}
          >
            <bdo dir="ltr">{file.path}</bdo>
          </span>
          <.button
            variant="neutral"
            size="xs"
            phx-click={@event}
            phx-value-id={file.id}
            data-nav-item
            tabindex="0"
          >
            Restore
          </.button>
        </li>
      </ul>
    </.disclosure>
    """
  end
end
