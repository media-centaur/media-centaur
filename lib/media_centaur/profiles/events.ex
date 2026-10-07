defmodule MediaCentaur.Profiles.Events do
  @moduledoc """
  Typed payloads for `profiles:updates` (ADR-060): one struct per
  message, a single `broadcast/1`. The one `Topics.publish` in the
  Profiles context.
  """

  alias MediaCentaur.Profiles.Profile
  alias MediaCentaur.Topics

  defmodule ProfileAdded do
    @moduledoc "A profile was added."
    @enforce_keys [:profile]
    defstruct [:profile]
    @type t :: %__MODULE__{profile: Profile.t()}
  end

  defmodule ProfileChanged do
    @moduledoc "A profile's name, hue or picture changed; the struct is the row after the change."
    @enforce_keys [:profile]
    defstruct [:profile]
    @type t :: %__MODULE__{profile: Profile.t()}
  end

  defmodule ProfileRemoved do
    @moduledoc "A profile was removed; a session using it drops to the picker."
    @enforce_keys [:id]
    defstruct [:id]
    @type t :: %__MODULE__{id: Ecto.UUID.t()}
  end

  @type t :: ProfileAdded.t() | ProfileChanged.t() | ProfileRemoved.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ProfileAdded{} = event), do: publish({:profile_added, event})
  def broadcast(%ProfileChanged{} = event), do: publish({:profile_changed, event})
  def broadcast(%ProfileRemoved{} = event), do: publish({:profile_removed, event})

  defp publish(message), do: Topics.publish(Topics.profiles_updates(), message)
end
