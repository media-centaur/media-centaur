defmodule MediaCentaur.Playback.Remembered do
  @moduledoc """
  A viewing's remembered playback settings: the title they belong to and
  the profile's `Library.PlaybackOverride` for it, loaded once when the
  session starts (`load/2`) and saved whenever the viewer moves a setting
  away from it (`save/3`).

  The owner is the title watched as a unit: a movie, or the series an
  episode belongs to — so a setting changed in one episode holds for the
  whole show. An extra or an unattributed file has no owner; nothing is
  remembered for it (`remembers?/1`).

  Each setting compares against its own default and contributes only its
  own fields to a save, so one never disturbs another:

    * **Tracks** — against the language policy's choice
      (`LanguageContext.capture/2`, `OverrideCapture`).
    * **Picture** — against Fit (`picture_change/2`): Fill width is the
      only divergence.

  Every save broadcasts `Events.PlaybackOverrideChanged`, so an open detail
  page's *Remembered settings* badge follows.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Format, Iso639, Library}
  alias MediaCentaur.Library.PlaybackOverride
  alias MediaCentaur.Playback.{Entry, Events}

  defstruct [:owner_type, :owner_id, :original_language, :override]

  @type t :: %__MODULE__{
          owner_type: :tv_series | :movie | nil,
          owner_id: String.t() | nil,
          original_language: String.t() | nil,
          override: PlaybackOverride.t() | nil
        }

  @doc """
  The remembered settings for `profile_id`'s viewing of `entry`: its owner,
  the owner's original language (ISO 639-2/T, for the language policy) and
  the profile's override, if any. An entry with no owner remembers nothing.
  """
  @spec load(String.t(), Entry.t()) :: t()
  def load(profile_id, %Entry{} = entry) when is_binary(profile_id) do
    case owner(entry) do
      {owner_type, owner_id, original_language} ->
        %__MODULE__{
          owner_type: owner_type,
          owner_id: owner_id,
          original_language: original_language,
          override: Library.PlaybackOverrides.get(profile_id, owner_type, owner_id)
        }

      nil ->
        %__MODULE__{}
    end
  end

  @doc "Whether the viewing has a title to remember settings for."
  @spec remembers?(t()) :: boolean()
  def remembers?(%__MODULE__{owner_type: owner_type}), do: not is_nil(owner_type)

  @doc "Whether the picture is remembered as filling the screen's width (else Fit, the default)."
  @spec fill_width?(t()) :: boolean()
  def fill_width?(%__MODULE__{override: %PlaybackOverride{fill_width: true}}), do: true
  def fill_width?(%__MODULE__{}), do: false

  @doc """
  The picture fields to save for the viewer's current picture setting
  (`fill_width`, as the player reports it): none when it matches what is
  remembered, or while the player has not reported it yet (`nil`).
  """
  @spec picture_change(t(), boolean() | nil) :: map()
  def picture_change(%__MODULE__{}, nil), do: %{}

  def picture_change(%__MODULE__{} = remembered, fill_width) when is_boolean(fill_width) do
    if fill_width == fill_width?(remembered), do: %{}, else: %{fill_width: fill_width}
  end

  @doc """
  Saves `attrs` into `profile_id`'s override for the owner — only the
  fields given; the rest keep what they held — and broadcasts the change.
  Returns the remembered settings with the saved row, or unchanged when
  there is nothing to save or the write fails.
  """
  @spec save(t(), String.t(), map()) :: t()
  def save(%__MODULE__{} = remembered, _profile_id, attrs) when attrs == %{}, do: remembered

  def save(%__MODULE__{owner_type: owner_type, owner_id: owner_id} = remembered, profile_id, attrs)
      when is_binary(profile_id) and is_map(attrs) do
    case Library.PlaybackOverrides.upsert(profile_id, owner_type, owner_id, attrs) do
      {:ok, override} ->
        Log.info(
          :playback,
          "saved playback override (#{owner_type}=#{Format.short_id(owner_id)}) — #{inspect(attrs)}"
        )

        Events.broadcast(%Events.PlaybackOverrideChanged{
          profile_id: profile_id,
          owner_type: owner_type,
          owner_id: owner_id
        })

        %{remembered | override: override}

      {:error, changeset} ->
        Log.warning(:playback, "failed to save playback override — #{inspect(changeset.errors)}")
        remembered
    end
  end

  defp owner(%Entry{extra_id: extra_id}) when is_binary(extra_id), do: nil

  defp owner(%Entry{movie_id: movie_id}) when is_binary(movie_id) do
    case Library.Containers.fetch(:movie, movie_id) do
      {:ok, movie} -> {:movie, movie.id, Iso639.normalize(movie.original_language)}
      _ -> nil
    end
  end

  # An episode's owner is the series root, which `entity_id` already is.
  defp owner(%Entry{episode_id: episode_id, entity_id: entity_id})
       when is_binary(episode_id) and is_binary(entity_id) do
    case Library.Containers.fetch(:tv_series, entity_id) do
      {:ok, series} -> {:tv_series, series.id, Iso639.normalize(series.original_language)}
      _ -> nil
    end
  end

  defp owner(%Entry{}), do: nil
end
