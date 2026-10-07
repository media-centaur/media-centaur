defmodule MediaCentaur.Profiles do
  use Boundary,
    deps: [],
    exports: [
      Events,
      Events.ProfileAdded,
      Events.ProfileChanged,
      Events.ProfileRemoved,
      PictureStore,
      Profile
    ]

  @moduledoc """
  Bounded context for the people who watch on this install (ADR-078):
  one `Profile` per person — a name, a hue, a picture — picked on the
  screen (`/profiles`, UIDR-053) and edited under Settings → Profiles.
  Phase 2 makes the watching rows theirs. Nothing here knows which
  profile a session is using; that is the web layer's (`Live.ProfileAware`).

  At most `max_profiles/0` profiles; never fewer than one through
  `remove/1`. Broadcasts typed events on `profiles:updates`
  (`subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Hue
  alias MediaCentaur.Profiles.Events
  alias MediaCentaur.Profiles.PictureStore
  alias MediaCentaur.Profiles.Profile
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @max_profiles 8

  @typedoc "What `set_picture/2` does: remove the picture, or set the WebP master `ImageFiles.webp_master/4` made."
  @type picture_change :: :none | {:new, binary()}

  @doc "Subscribe the caller to profile events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.profiles_updates())

  @doc "The most profiles an install holds."
  @spec max_profiles() :: pos_integer()
  def max_profiles, do: @max_profiles

  @doc "Every profile, oldest first — the owner profile leads."
  @spec list() :: [Profile.t()]
  def list, do: Repo.all(from profile in Profile, order_by: [asc: profile.inserted_at, asc: profile.id])

  @doc "A profile by id; nil for an unknown or malformed id."
  @spec get(String.t()) :: Profile.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Profile, uuid)
      :error -> nil
    end
  end

  def get(_not_a_string), do: nil

  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(Profile, :count)

  @doc "Adds a profile under `DisplayName.check/1`, below the cap. Broadcasts `ProfileAdded`."
  @spec add(String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long | :too_many_profiles}
  def add(name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name),
         :ok <- under_cap() do
      {:ok, profile} = %Profile{} |> Profile.changeset(%{name: name}) |> Repo.insert()
      Events.broadcast(%Events.ProfileAdded{profile: profile})
      {:ok, profile}
    end
  end

  @doc "Renames under `DisplayName.check/1`. Broadcasts `ProfileChanged`."
  @spec rename(Profile.t(), String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long}
  def rename(%Profile{} = profile, name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name) do
      profile |> Profile.changeset(%{name: name}) |> update_and_broadcast()
    end
  end

  @doc "Sets the hue (UIDR-048), nil for none; out of range is refused. Broadcasts `ProfileChanged`."
  @spec set_hue(Profile.t(), Hue.t() | nil) :: {:ok, Profile.t()} | {:error, :invalid_hue}
  def set_hue(%Profile{} = profile, nil),
    do: profile |> Profile.changeset(%{hue: nil}) |> update_and_broadcast()

  def set_hue(%Profile{} = profile, hue) do
    if Hue.valid?(hue),
      do: profile |> Profile.changeset(%{hue: hue}) |> update_and_broadcast(),
      else: {:error, :invalid_hue}
  end

  @doc """
  Sets or removes the picture: the row first, then the file, so a write
  that fails after the row reads as no picture until the next save
  rather than serving new bytes under the old URL. Broadcasts `ProfileChanged`.
  """
  @spec set_picture(Profile.t(), picture_change()) :: {:ok, Profile.t()}
  def set_picture(%Profile{} = profile, :none) do
    {:ok, updated} = profile |> Profile.changeset(%{picture_at: nil}) |> update_and_broadcast()
    if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
    {:ok, updated}
  end

  def set_picture(%Profile{} = profile, {:new, bytes}) when is_binary(bytes) do
    now = DateTime.utc_now(:second)
    {:ok, updated} = profile |> Profile.changeset(%{picture_at: now}) |> update_and_broadcast()
    :ok = PictureStore.write(profile.id, bytes)
    {:ok, updated}
  end

  @doc "The picture's versioned URL, or nil when the profile has none or the file is missing."
  @spec picture_url(Profile.t()) :: String.t() | nil
  def picture_url(%Profile{picture_at: nil}), do: nil
  def picture_url(%Profile{id: id, picture_at: at}), do: PictureStore.url(id, DateTime.to_unix(at))

  @doc """
  Removes a profile and its picture. Refuses the last one: the install
  always has someone to watch as. Phase 2 cascades the watching rows by
  foreign key. Broadcasts `ProfileRemoved`.
  """
  @spec remove(Profile.t()) :: :ok | {:error, :last_profile}
  def remove(%Profile{} = profile) do
    if count() <= 1 do
      {:error, :last_profile}
    else
      {:ok, _deleted} = Repo.delete(profile)
      if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
      Events.broadcast(%Events.ProfileRemoved{id: profile.id})
      :ok
    end
  end

  defp under_cap, do: if(count() < @max_profiles, do: :ok, else: {:error, :too_many_profiles})

  defp update_and_broadcast(changeset) do
    with {:ok, profile} <- Repo.update(changeset) do
      Events.broadcast(%Events.ProfileChanged{profile: profile})
      {:ok, profile}
    end
  end
end
