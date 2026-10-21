defmodule MediaCentaurWeb.Components.Social.ToolbarSlots do
  @moduledoc """
  The two resolved positions of a row's toolbar (UIDR-045, UIDR-046)
  and the three facts they come from: the title's rung on the reader's
  watchlist, the library entity that owns it, and its acquisition
  state. Facts about the reader and a title, never about an action —
  one value per title, carried by every row for it: the Feed's row for
  one action and the person page's row for one title.

  `list` is what the List position holds: the verb `:list`, the filled
  `:listed`, or the state `:following` (Follow and above; the row
  renders it as "Tracking"). `download` is the verb `:download` or
  `{:state, word}` — "In library", or the acquisition marker while a
  plan runs (`Logic.acquisition_marker/1`, so no state is spelled
  twice). A view-model, resolved by the host; the row decides nothing.
  """

  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaurWeb.Components.Title.Logic

  defstruct [:rung, :library_owner_id, :acquisition_state, :list, :download]

  @type list_slot :: :list | :listed | :following
  @type download_slot :: :download | {:state, String.t()}

  @type t :: %__MODULE__{
          rung: TitleIntent.rung() | nil,
          library_owner_id: Ecto.UUID.t() | nil,
          acquisition_state: atom() | nil,
          list: list_slot(),
          download: download_slot()
        }

  @doc "The slots for an enriched activity row, or any map carrying the three facts."
  @spec resolve(%{
          required(:rung) => TitleIntent.rung() | nil,
          required(:library_owner_id) => term() | nil,
          required(:acquisition_state) => atom() | nil,
          optional(atom()) => term()
        }) :: t()
  def resolve(%{rung: rung, library_owner_id: owner, acquisition_state: state}) do
    %__MODULE__{
      rung: rung,
      library_owner_id: owner,
      acquisition_state: state,
      list: list_slot(rung),
      download: download_slot(owner, state)
    }
  end

  defp list_slot(:list), do: :listed
  defp list_slot(rung), do: if(TitleIntent.follows_releases?(rung), do: :following, else: :list)

  defp download_slot(owner, _state) when not is_nil(owner), do: {:state, "In library"}

  defp download_slot(nil, state) do
    case Logic.acquisition_marker(state) do
      nil -> :download
      word -> {:state, word}
    end
  end
end
