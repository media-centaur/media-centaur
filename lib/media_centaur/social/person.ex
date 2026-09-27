defmodule MediaCentaur.Social.Person do
  @moduledoc """
  A public key as this reader sees it (ADR-074, UIDR-047).
  `name_override` is the reader's word for a friend (nil for the
  reader's own); `published_name` is what the key said about itself
  (`Social.Profile`); `name/1` resolves them. The avatar URL is nil
  until the profiles campaign's phase 3 fills it; the tile already draws
  one. `own?` says whether the key is the reader's own. Built in the app only by `Social.people/0` and
  `Social.own_person/0`; every surface that draws a person takes one.
  "You" is `MediaCentaur.Format.person_name/1`'s word for `own?`, never
  data here.

  `pubkey` is nil for the reader before an identity exists: the review
  modal previews as the reader all the same. `added_on` is nil for the
  reader's own.

  Not `MediaCentaur.Library.Person`, which is a title's cast member.
  """

  defstruct [:pubkey, :name_override, :published_name, :avatar_url, :short_npub, :added_on, own?: false]

  @type t :: %__MODULE__{
          pubkey: String.t() | nil,
          name_override: String.t() | nil,
          published_name: String.t() | nil,
          avatar_url: String.t() | nil,
          own?: boolean(),
          short_npub: String.t() | nil,
          added_on: Date.t() | nil
        }

  @doc "The name the reader sees: the override, else the published name, else nil."
  @spec name(t()) :: String.t() | nil
  def name(%__MODULE__{name_override: override, published_name: published}), do: override || published
end
