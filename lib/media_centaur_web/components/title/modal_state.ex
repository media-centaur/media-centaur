defmodule MediaCentaurWeb.Components.Title.ModalState do
  @moduledoc """
  The per-opening UI state of the title detail modal — what the host
  owns and the renderer reads, and what means nothing once the subject
  changes: which view is showing, which seasons and disclosures are
  open, what the cast filter says, which destructive act is armed or
  running, whether a TMDB check is in flight, which glass menu is open,
  which scope choice the select shows, whether the *Grab new episodes
  as they air* switch is on, and the one plan in flight.

  One struct on the socket, replaced by `new/1` whenever the subject
  changes and on close, so nothing armed against one title survives
  onto the next. `view` is the runtime instance of the `?view=` param —
  only `handle_params` writes it. `expanded_seasons` is seeded from
  `ViewModel.Orientation` when the entry is a series (`new/2`).

  The scope and the grab switch move together: `choose_scope/2` sets the
  scope and the switch's default for it (on for *Latest season*, off
  otherwise), and the person's own flip (`toggle_grab_rest/1`) holds
  until the next choice. Which scopes a title is offered, and whether
  the switch is offered at all, are the detail's facts
  (`Title.Logic.offered_scopes/1`, `grab_rest_offered?/3`).
  """

  alias MediaCentaur.Acquisition.Plans.DownloadScope

  @scope_choices DownloadScope.scopes() ++ [:choose_episodes]

  @typedoc """
  The scope select's value: a rule `DownloadScope` resolves to episodes,
  or `:choose_episodes` — the person picks them in the picker on Downloads,
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
            deleting: nil,
            tmdb_checking: false,
            all_subtitles: false,
            open_menu: nil,
            download_scope: :first_missing_season,
            grab_rest: false,
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
          deleting: delete_target(),
          tmdb_checking: boolean(),
          all_subtitles: boolean(),
          open_menu: nil | :mode | :scope | :social | :caught_up_season | :caught_up_episode,
          download_scope: scope_choice(),
          grab_rest: boolean(),
          pending: nil | {:download, String.t()} | {:missing_episode, {pos_integer(), pos_integer()}}
        }

  @doc "A fresh state on `view`, nothing expanded, armed, typed or pending."
  @spec new(view()) :: t()
  def new(view \\ :main) when view in [:main, :cast, :info], do: %__MODULE__{view: view}

  @doc "A fresh state with the seasons a series opens expanded."
  @spec new(view(), MapSet.t(pos_integer())) :: t()
  def new(view, %MapSet{} = expanded_seasons), do: %{new(view) | expanded_seasons: expanded_seasons}

  @doc "Puts the scope select on `scope`, with the grab switch at its default for it, menu closed."
  @spec choose_scope(t(), scope_choice()) :: t()
  def choose_scope(%__MODULE__{} = state, scope) when scope in @scope_choices,
    do: %{state | download_scope: scope, grab_rest: scope == :latest_season, open_menu: nil}

  @doc "Flips the *Grab new episodes as they air* switch."
  @spec toggle_grab_rest(t()) :: t()
  def toggle_grab_rest(%__MODULE__{} = state), do: %{state | grab_rest: not state.grab_rest}

  @doc "Every value the scope select can hold, in menu order."
  @spec scope_choices() :: [scope_choice()]
  def scope_choices, do: @scope_choices

  @doc "The select's value from its wire form — a closed set, mapped explicitly."
  @spec parse_scope_choice(term()) :: {:ok, scope_choice()} | :error
  def parse_scope_choice(choice) when is_binary(choice) do
    case Enum.find(@scope_choices, &(Atom.to_string(&1) == choice)) do
      nil -> :error
      scope -> {:ok, scope}
    end
  end

  def parse_scope_choice(_other), do: :error
end
