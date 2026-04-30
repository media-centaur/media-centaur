defmodule MediaCentarr.Acquisition.SearchSession do
  @moduledoc """
  Singleton GenServer holding the user's current acquisition search session.

  Decouples the search workflow from `MediaCentarrWeb.AcquisitionLive`'s
  process lifetime so search state — query, brace-expanded groups, results,
  user selections, grab feedback — survives navigation, reconnect, and
  browser refresh. Lost on BEAM restart.

  All public access goes through the `MediaCentarr.Acquisition` facade —
  no module outside the Acquisition context calls this GenServer directly.

  See `docs/superpowers/specs/2026-04-30-acquisition-search-session-design.md`.
  """

  use GenServer

  alias MediaCentarr.Acquisition.SearchResult

  @type group_status :: :loading | :ready | {:failed, term()} | :abandoned

  @type group :: %{
          term: String.t(),
          status: group_status(),
          results: [SearchResult.t()],
          expanded?: boolean()
        }

  @type t :: %__MODULE__{
          query: String.t(),
          expansion_preview: :idle | {:ok, pos_integer()} | {:error, atom()},
          groups: [group()],
          selections: %{String.t() => String.t()},
          grab_message: nil | {:ok | :partial | :error, String.t()},
          grabbing?: boolean(),
          searching_pid: nil | pid()
        }

  defstruct query: "",
            expansion_preview: :idle,
            groups: [],
            selections: %{},
            grab_message: nil,
            grabbing?: false,
            searching_pid: nil

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the current session struct."
  @spec current(GenServer.server()) :: t()
  def current(server \\ __MODULE__) do
    GenServer.call(server, :current)
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call(:current, _from, state) do
    {:reply, state, state}
  end
end
