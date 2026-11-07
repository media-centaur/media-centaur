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

  Audio, subtitles and the picture are three settings, each saved on its
  own: a save carries only the fields of the settings the viewer changed,
  compared with what was in effect, so one never disturbs another.

    * **Tracks** — `LanguageContext.capture/2` (`OverrideCapture`).
    * **Picture** — `picture_change/2`: Fit or Fill width.

  A setting goes back to its default only when the viewer asks for it
  (`use_default/3`, the menu's **Default**), which clears that setting and
  nothing else.

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

  @doc "Whether `setting` follows its default for this title."
  @spec follows_default?(t(), PlaybackOverride.setting()) :: boolean()
  def follows_default?(%__MODULE__{override: override}, setting),
    do: PlaybackOverride.follows_default?(override, setting)

  @doc "Whether the picture fills the screen's width for this title (else Fit, chosen or by default)."
  @spec fill_width?(t()) :: boolean()
  def fill_width?(%__MODULE__{override: %PlaybackOverride{fill_width: true}}), do: true
  def fill_width?(%__MODULE__{}), do: false

  @doc """
  The picture fields to save for the viewer's current picture setting
  (`fill_width`, as the player reports it): the choice when it differs
  from what is in effect, none when it matches or while the player has not
  reported it yet (`nil`).
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

  @doc """
  Puts `setting` back on its default for `profile_id`'s title, leaving the
  other settings as they are. Nothing is written when it already follows
  its default.
  """
  @spec use_default(t(), String.t(), PlaybackOverride.setting()) :: t()
  def use_default(%__MODULE__{} = remembered, profile_id, setting) do
    if remembers?(remembered) and not follows_default?(remembered, setting),
      do: save(remembered, profile_id, PlaybackOverride.default_attrs(setting)),
      else: remembered
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
