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

  @doc """
  The owner profile: the oldest one, which the upgrade created and every
  watching row from before profiles was assigned to. Never nil — the
  install always has a profile (`remove/1` refuses the last).
  """
  @spec owner() :: Profile.t()
  def owner, do: hd(list())

  @doc "A profile by id; nil for an unknown or malformed id."
  @spec get(String.t()) :: Profile.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Profile, uuid)
      :error -> nil
    end
  end

  def get(_not_a_string), do: nil

  @doc "How many profiles the install holds."
  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(Profile, :count)

  @doc """
  Adds a profile under `DisplayName.check/1`, below the cap, born with
  the first palette hue no profile holds (`Hue.first_unused/1`) so the
  people of the install differ at a glance. Broadcasts `ProfileAdded`.
  """
  @spec add(String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long | :too_many_profiles}
  def add(name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name),
         {:ok, profile} <- insert_under_cap(name) do
      Events.broadcast(%Events.ProfileAdded{profile: profile})
      {:ok, profile}
    end
  end

  # The read of the others, the cap check and the insert share one
  # immediate transaction, so two adds cannot both pass the cap or both
  # take one hue.
  defp insert_under_cap(name) do
    Repo.transaction(
      fn ->
        others = list()

        if length(others) < @max_profiles do
          hue = Hue.first_unused(Enum.map(others, & &1.hue))
          %Profile{} |> Profile.changeset(%{name: name, hue: hue}) |> Repo.insert!()
        else
          Repo.rollback(:too_many_profiles)
        end
      end,
      mode: :immediate
    )
  end

  @doc "Renames under `DisplayName.check/1`. Broadcasts `ProfileChanged`."
  @spec rename(Profile.t(), String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long}
  def rename(%Profile{} = profile, name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name) do
      profile |> Profile.changeset(%{name: name}) |> update_and_broadcast()
    end
  end

  @doc "Sets the hue (UIDR-048); out of range, or none, is refused. Broadcasts `ProfileChanged`."
  @spec set_hue(Profile.t(), Hue.t()) :: {:ok, Profile.t()} | {:error, :invalid_hue}
  def set_hue(%Profile{} = profile, hue) do
    if Hue.valid?(hue),
      do: profile |> Profile.changeset(%{hue: hue}) |> update_and_broadcast(),
      else: {:error, :invalid_hue}
  end

  @doc """
  Sets or removes the picture: the row first, then the file, so new
  bytes are never served under the old URL. A write that fails after the
  row reads as no picture until the next save when there was no file
  before, and as the old picture under the new version when there was.
  Broadcasts `ProfileChanged` only once the file has landed or gone, so
  a session never fetches the new URL ahead of its bytes.
  """
  @spec set_picture(Profile.t(), picture_change()) :: {:ok, Profile.t()}
  def set_picture(%Profile{} = profile, :none) do
    updated = profile |> Profile.changeset(%{picture_at: nil}) |> update!()
    if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
    Events.broadcast(%Events.ProfileChanged{profile: updated})
    {:ok, updated}
  end

  def set_picture(%Profile{} = profile, {:new, bytes}) when is_binary(bytes) do
    updated = profile |> Profile.changeset(%{picture_at: DateTime.utc_now()}) |> update!()
    :ok = PictureStore.write(profile.id, bytes)
    Events.broadcast(%Events.ProfileChanged{profile: updated})
    {:ok, updated}
  end

  @doc "The picture's versioned URL, or nil when the profile has none or the file is missing."
  @spec picture_url(Profile.t()) :: String.t() | nil
  def picture_url(%Profile{picture_at: nil}), do: nil

  def picture_url(%Profile{id: id, picture_at: at}),
    do: PictureStore.url(id, DateTime.to_unix(at, :microsecond))

  @doc """
  Removes a profile and its picture. Refuses the last one: the install
  always has someone to watch as. A profile already removed answers `:ok`
  and broadcasts nothing. The watching rows go with it by foreign key
  (`ON DELETE CASCADE` on the four tables). Broadcasts `ProfileRemoved`.
  """
  @spec remove(Profile.t()) :: :ok | {:error, :last_profile}
  def remove(%Profile{} = profile) do
    case delete_unless_last(profile) do
      {:ok, :removed} ->
        if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
        Events.broadcast(%Events.ProfileRemoved{id: profile.id})
        :ok

      {:ok, :already_removed} ->
        :ok

      {:error, :last_profile} ->
        {:error, :last_profile}
    end
  end

  # The delete and the count share one immediate transaction, so two
  # removes cannot together take the install to no profile. Deleting
  # first lets an already removed row answer before the count.
  defp delete_unless_last(profile) do
    Repo.transaction(
      fn ->
        case Repo.delete(profile, stale_error_field: :id) do
          {:ok, _deleted} -> if count() == 0, do: Repo.rollback(:last_profile), else: :removed
          {:error, _stale} -> :already_removed
        end
      end,
      mode: :immediate
    )
  end

  defp update!(changeset) do
    {:ok, profile} = Repo.update(changeset)
    profile
  end

  # An unchanged row is no change: nothing is written or broadcast.
  defp update_and_broadcast(%Ecto.Changeset{changes: changes, data: profile}) when changes == %{},
    do: {:ok, profile}

  defp update_and_broadcast(changeset) do
    profile = update!(changeset)
    Events.broadcast(%Events.ProfileChanged{profile: profile})
    {:ok, profile}
  end
end
