defmodule MediaCentaurWeb.ProfileWords do
  @moduledoc """
  The words for what a person-record form refused — a viewer profile's
  card and the social profile's card share them, since they share the
  rules (`MediaCentaur.DisplayName`, `MediaCentaur.Hue`, the picture
  field). One place, so the two cards never say the same thing two ways.
  An unknown reason is a bug, so `error/1` crashes on it rather than
  guess at words.
  """

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles

  @typedoc "A refusal a person-record form can meet."
  @type reason ::
          :name_required
          | :name_too_long
          | :bad_image
          | :too_large
          | :avatar_too_large
          | :invalid_hue
          | :too_many_profiles
          | :last_profile

  @spec error(reason()) :: String.t()
  def error(:name_required), do: "A profile needs a name"
  def error(:name_too_long), do: "Names are at most #{DisplayName.max_length()} characters"
  def error(:bad_image), do: "That file is not a picture we can read"
  def error(:too_large), do: "That picture cannot be made small enough"
  def error(:avatar_too_large), do: error(:too_large)
  def error(:invalid_hue), do: "That colour cannot be used"

  def error(:too_many_profiles),
    do: "#{number_word(Profiles.max_profiles())} profiles is the most this install holds"

  def error(:last_profile), do: "The last profile can't be removed"

  defp number_word(8), do: "Eight"
  defp number_word(number), do: Integer.to_string(number)
end
