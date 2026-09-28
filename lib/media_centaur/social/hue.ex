defmodule MediaCentaur.Social.Hue do
  @moduledoc """
  A person's colour is a hue (UIDR-048): an integer angle 0–359 on one
  oklch ring whose lightness and chroma the theme fixes (`--person-l`,
  `--person-c` in `app.css`), so nothing published can be dark, pastel
  or grey and a letter's contrast never depends on the choice. On the
  wire it is the profile's optional `hue` field (ADR-073); in the row,
  `profiles.hue` and the reader's `friends.hue_override`. User copy says
  *colour*; code and the wire say hue.

  The palette is the eight named angles the swatch row offers; any
  other angle comes from the slider. `random/0` seeds a new profile's
  form. A person with no hue is drawn at 250, the primary's angle, by
  CSS alone (`var(--hue, 250)`); no function here supplies a default.
  """

  @type t :: 0..359

  @palette [
    {"Rose", 12},
    {"Orange", 45},
    {"Amber", 80},
    {"Green", 150},
    {"Teal", 195},
    {"Blue", 250},
    {"Violet", 290},
    {"Magenta", 335}
  ]

  @doc "Whether a term is a hue: an integer 0–359. A float is not."
  @spec valid?(term()) :: boolean()
  def valid?(hue), do: is_integer(hue) and hue >= 0 and hue <= 359

  @doc "The eight named hues the swatch row offers, in ring order."
  @spec palette() :: [{String.t(), t()}]
  def palette, do: @palette

  @doc "A palette hue at random: the seed for a profile that has none yet."
  @spec random() :: t()
  def random, do: @palette |> Enum.random() |> elem(1)

  @doc "A form value as a hue: the angle, nil for empty or absent, `:error` for anything else."
  @spec parse(String.t() | nil) :: {:ok, t() | nil} | :error
  def parse(nil), do: {:ok, nil}
  def parse(""), do: {:ok, nil}

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {hue, ""} -> if valid?(hue), do: {:ok, hue}, else: :error
      _other -> :error
    end
  end
end
