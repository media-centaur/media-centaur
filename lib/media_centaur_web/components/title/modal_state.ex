defmodule MediaCentaurWeb.Components.Title.ModalState do
  @moduledoc """
  The per-opening UI state of the title detail modal — what the host
  owns and the renderer reads, and what means nothing once the subject
  changes: which view is showing, which seasons and disclosures are
  open, what the cast filter says, which destructive act is armed or
  running, whether a TMDB check is in flight, which glass menu is open,
  which scope choice the select shows, and the one plan in flight.

  One struct on the socket, replaced by `new/1` whenever the subject
  changes and on close, so nothing armed against one title survives
  onto the next. `view` is the runtime instance of the `?view=` param —
  only `handle_params` writes it. `expanded_seasons` is seeded from
  `ViewModel.Orientation` when the entry is a series (`new/2`).
  """

  alias MediaCentaur.Acquisition.Plans.DownloadScope

  @scope_choices [:first_season, :everything, :choose_episodes]

  @typedoc """
  The scope select's value: a rule `DownloadScope` resolves to episodes,
  or `:choose_episodes` — the person picks them in the picker on Incoming,
  so the Download control opens it instead of planning (spec 2026-09-23
  §1, §3). Not a `DownloadScope.scope/0`: it resolves to nothing here.
  """
  @type scope_choice :: DownloadScope.scope() | :choose_episodes

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
            tmdb_checking: false,
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
          tmdb_checking: boolean(),
          open_menu: nil | :mode | :scope,
          download_scope: scope_choice(),
          pending: nil | {:download, String.t()} | {:missing_episode, {pos_integer(), pos_integer()}}
        }

  @doc "A fresh state on `view`, nothing expanded, armed, typed or pending."
  @spec new(view()) :: t()
  def new(view \\ :main) when view in [:main, :cast, :info], do: %__MODULE__{view: view}

  @doc "A fresh state with the seasons a series opens expanded."
  @spec new(view(), MapSet.t(pos_integer())) :: t()
  def new(view, %MapSet{} = expanded_seasons), do: %{new(view) | expanded_seasons: expanded_seasons}

  @doc "Every value the scope select offers, in menu order."
  @spec scope_choices() :: [scope_choice()]
  def scope_choices, do: @scope_choices

  @doc "The select's value from its wire form — a closed set, mapped explicitly."
  @spec parse_scope_choice(term()) :: {:ok, scope_choice()} | :error
  def parse_scope_choice("first_season"), do: {:ok, :first_season}
  def parse_scope_choice("everything"), do: {:ok, :everything}
  def parse_scope_choice("choose_episodes"), do: {:ok, :choose_episodes}
  def parse_scope_choice(_other), do: :error
end
