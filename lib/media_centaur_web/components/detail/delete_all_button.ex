defmodule MediaCentaurWeb.Components.Detail.DeleteAllButton do
  @moduledoc """
  The title's primary delete: every file the library holds for it, as
  one click-twice gesture (`delete_all_prompt`, `MediaCentaurWeb.Live.ArmGesture`).
  The finish prompt draws it for one movie of a collection with
  `target={{:member, id}}` and that movie's files: the event carries
  `phx-value-member`, so the collection's `:all` is never armed.
  One file reads "Delete this file", several "Delete all files", each
  with the total size. Drawn by the Manage panel's toolbar and by the
  finish prompt; both send the same event to `TitleDetailHost`, which
  owns the gesture, the async delete and the playing guard.

  Nothing is drawn until the file list has loaded and holds a file: an
  empty list is only "no files" once the load has finished.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LiveHelpers, only: [delete_gesture_state: 3, delete_in_flight?: 1]

  alias MediaCentaurWeb.Components.Detail.ManagePanel

  attr :files, :list,
    required: true,
    doc: "file-info maps (`%{file: KnownFile.t(), size: bytes | nil}`) from the host's file-info load."

  attr :files_status, :atom, values: [:loading, :loaded, :failed], default: :loaded

  attr :target, :any,
    default: :all,
    doc: "what this button deletes: `:all`, or `{:member, movie_id}` for one movie of a collection."

  attr :delete_confirm, :any,
    default: nil,
    doc: "the armed delete target (this button's `target` arms it); any other target leaves it resting."

  attr :deleting, :any,
    default: nil,
    doc: "the in-flight delete target; any target disables the button, its own `target` shows it busy."

  def delete_all_button(assigns) do
    file_count = length(assigns.files)
    total_size = Enum.reduce(assigns.files, 0, fn %{size: size}, acc -> acc + (size || 0) end)
    label = "#{label(file_count)} (#{ManagePanel.format_file_size(total_size)})"

    assigns =
      assigns
      |> assign(:gesture, delete_gesture_state(assigns.target, assigns.deleting, assigns.delete_confirm))
      |> assign(:member_id, member_id(assigns.target))
      |> assign(:label, label)
      |> assign(:aria_label, aria_label(file_count))

    ~H"""
    <.armed_button
      :if={@files != [] and @files_status == :loaded}
      armed={@gesture == :confirm}
      busy={@gesture == :deleting}
      busy_label={"Deleting… #{@label}"}
      event="delete_all_prompt"
      armed_label={"Click again to confirm — #{@label}"}
      variant="danger"
      size="sm"
      disabled={delete_in_flight?(@deleting)}
      aria-label={@aria_label}
      phx-value-member={@member_id}
    >
      <.icon name="hero-trash-mini" class="size-4" />
      {@label}
    </.armed_button>
    """
  end

  defp member_id({:member, id}), do: id
  defp member_id(:all), do: nil

  defp label(1), do: "Delete this file"
  defp label(_count), do: "Delete all files"

  defp aria_label(1), do: "Delete the file for this entry"
  defp aria_label(_count), do: "Delete all files for this entry"
end
