defmodule MediaCentaur.DisplayName do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The one rule for a person's name wherever the app holds one: the
  social profile's published name (`Social.save_profile/3`, the wire cap
  in `Social.Profile.Translation`) and a viewer profile's name
  (`Profiles`). Trimmed, present, and at most `max_length/0` characters.
  """

  @max_length 50

  @doc "The cap, in characters."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "The trimmed name, or why it was refused."
  @spec check(String.t()) :: {:ok, String.t()} | {:error, :name_required | :name_too_long}
  def check(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :name_required}
      String.length(trimmed) > @max_length -> {:error, :name_too_long}
      true -> {:ok, trimmed}
    end
  end
end
