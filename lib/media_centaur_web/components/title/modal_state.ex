defmodule MediaCentaurWeb.Components.Title.ModalState do
  @moduledoc """
  The per-opening UI state of the title detail modal — what the host
  owns and the renderer reads, and what means nothing once the subject
  changes: which view is showing, which seasons and disclosures are
  open, what the cast filter says, which destructive act is armed or
  running, which glass menu is open, which download scope is chosen,
  and the one plan in flight.

  One struct on the socket, replaced by `new/1` whenever the subject
  changes and on close, so nothing armed against one title survives
  onto the next. `view` is the runtime instance of the `?view=` param —
  only `handle_params` writes it. `expanded_seasons` is seeded from
  `ViewModel.Orientation` when the entry is a series (`new/2`).
  """

  defstruct view: :main,
            expanded_seasons: MapSet.new(),
            expanded_item_details: MapSet.new(),
            all_episode_details_open: false,
            expanded_file_groups: nil,
            cast_filter: "",
            cast_limit: nil,
            delete_confirm: nil,
            deleting: nil,
            rematch_confirm: false,
            open_menu: nil,
            download_scope: :first_season,
            pending: nil

  @type view :: :main | :cast | :info
  @type delete_target :: nil | :all | {:file, String.t()} | {:folder, String.t()}

  @type t :: %__MODULE__{
          view: view(),
          expanded_seasons: MapSet.t(pos_integer()),
          expanded_item_details: MapSet.t(String.t()),
          all_episode_details_open: boolean(),
          expanded_file_groups: MapSet.t(String.t()) | nil,
          cast_filter: String.t(),
          cast_limit: pos_integer() | nil,
          delete_confirm: delete_target(),
          deleting: delete_target(),
          rematch_confirm: boolean(),
          open_menu: nil | :mode | :scope,
          download_scope: :first_season | :everything,
          pending: nil | {:download, String.t()} | {:missing_episode, {pos_integer(), pos_integer()}}
        }

  @doc "A fresh state on `view`, nothing expanded, armed, typed or pending."
  @spec new(view()) :: t()
  def new(view \\ :main) when view in [:main, :cast, :info], do: %__MODULE__{view: view}

  @doc "A fresh state with the seasons a series opens expanded."
  @spec new(view(), MapSet.t(pos_integer())) :: t()
  def new(view, %MapSet{} = expanded_seasons), do: %{new(view) | expanded_seasons: expanded_seasons}
end
