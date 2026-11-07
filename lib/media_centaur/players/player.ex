defmodule MediaCentaur.Players.Player do
  @moduledoc """
  One paired player: a device on the LAN that renders a viewing, admitted
  to this install by pairing. The id is what the device's browser session
  holds (`"player_id"`, beside ADR-078's `"profile_id"`); the gate reads
  the row back on every request, so removing the row cuts the device off.

  Besides its name and `inserted_at` (when it paired), the row holds what
  the host learns of the device, each fact from its one source:

    * `device` — the app's own declaration (`Device`), sent with its
      channel when it opens. A device that never ran the app has none.
    * `user_agent` — the browser that shows the player's pages, as its
      LiveView socket reports it.
    * `last_seen_at`, `last_address` — when the player's channel last
      opened or closed, and the address it opened from.

  Whether the player is connected now is not here: that is the channel's
  live state, which Playback owns (`Playback.connected_players/0`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.DisplayName

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  defmodule Device do
    @moduledoc """
    A device's declaration of itself, sent by the app with its channel
    (`MediaCentaurWeb.Plugs.PlayerChannel` reads it from the upgrade's
    headers). `from_declaration/1` keeps each value that fits and drops
    the rest: a declaration is the device's word, not a contract.
    """
    use Ecto.Schema

    @max_length 100
    @form_factors [:tv, :phone, :tablet]

    @primary_key false
    embedded_schema do
      field :model, :string
      field :os, :string
      field :app_version, :string
      field :form_factor, Ecto.Enum, values: @form_factors
    end

    @type t :: %__MODULE__{
            model: String.t() | nil,
            os: String.t() | nil,
            app_version: String.t() | nil,
            form_factor: :tv | :phone | :tablet | nil
          }

    @doc """
    The device a declaration (string keys `model`, `os`, `app_version`,
    `form_factor`) describes: each text value trimmed, present and at
    most #{@max_length} characters, the form factor one of
    #{inspect(@form_factors)}. Nil when nothing in it fits.
    """
    @spec from_declaration(map()) :: t() | nil
    def from_declaration(declaration) when is_map(declaration) do
      device = %__MODULE__{
        model: text(declaration["model"]),
        os: text(declaration["os"]),
        app_version: text(declaration["app_version"]),
        form_factor: form_factor(declaration["form_factor"])
      }

      if device != %__MODULE__{}, do: device
    end

    defp text(value) when is_binary(value) do
      trimmed = String.trim(value)

      if trimmed != "" and String.length(trimmed) <= @max_length and String.printable?(trimmed),
        do: trimmed
    end

    defp text(_value), do: nil

    defp form_factor(value) when is_binary(value),
      do: Enum.find(@form_factors, &(Atom.to_string(&1) == value))

    defp form_factor(_value), do: nil
  end

  schema "players" do
    field :name, :string
    embeds_one :device, Device, on_replace: :update
    field :user_agent, :string
    field :last_seen_at, :utc_datetime_usec
    field :last_address, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @typedoc """
  Which player: `:host` for the host player (admitted by address, no
  row), or a paired player's row id. The one representation of a
  player's identity everywhere in the host — sessions, events, topics,
  the socket's `:player` assign (`Playback.player/0` names it there).
  """
  @type id :: :host | Ecto.UUID.t()

  @doc "The name is already checked by `DisplayName.check/1`. This is the row's last guard."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(player \\ %__MODULE__{}, attrs) do
    player
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: DisplayName.max_length())
  end

  @doc """
  A channel opened or closed: `last_seen_at`, and from `attrs` the
  `last_address` and the `device` when given (`Device.t()`; nil keeps the
  one already held).
  """
  @spec seen_changeset(t(), map()) :: Ecto.Changeset.t()
  def seen_changeset(player, attrs) do
    changeset =
      player
      |> change(last_seen_at: DateTime.utc_now())
      |> cast(attrs, [:last_address])

    case attrs[:device] do
      %Device{} = device -> put_embed(changeset, :device, device)
      nil -> changeset
    end
  end
end
