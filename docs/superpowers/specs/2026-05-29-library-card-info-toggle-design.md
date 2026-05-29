# Library card info toggle

A Settings-level preference that hides the title/type/year footer beneath each
poster card on the library page, leaving a pure wall-of-posters view. Defaults
to ON.

This is also the first new runtime preference written against the typed
accessor + `*Aware` on_mount trait pattern, replacing the older
`MediaCentaur.Config.update/get` façade for non-bootstrap state. The broader
migration of existing runtime-settable keys is tracked in
`campaigns/runtime-prefs-out-of-toml.md`.

## Decisions

* Persist via `MediaCentaur.Settings` directly (no `Config` involvement).
  Key: `"library_show_card_info"`, value shape `%{"enabled" => boolean}`.
* Default ON when the Settings entry is missing.
* Typed accessor module `MediaCentaur.LibraryCardInfo` mirrors
  `MediaCentaur.SpoilerFree`.
* LiveView wiring via a `MediaCentaurWeb.Live.LibraryCardInfoAware` on_mount
  trait, mirroring `SpoilerFreeAware`. Only consumer at ship time is
  `LibraryLive`; the trait keeps the wiring symmetric with `SpoilerFree` and
  lets `EntityModal` or detail surfaces opt in later without refactor.
* Settings UI: instant-toggle button in the existing Library section, modelled
  on `toggle_spoiler_free` (not part of the existing `#settings-library`
  Save form).
* Component contract: `LibraryCards.poster_card` gains a typed
  `:show_info, :boolean, default: true` attr; footer block wrapped in
  `:if={@show_info}`.
* Storybook: add a `show_info: false` variation to the existing
  `poster_card.story.exs` (MC0009 compliance for the new attr).

## Modules

### `MediaCentaur.LibraryCardInfo`

```elixir
defmodule MediaCentaur.LibraryCardInfo do
  use Boundary, deps: [MediaCentaur.Settings]

  @moduledoc """
  Typed accessor for the `library_show_card_info` Settings entry.

  Controls whether the poster card footer (title + type/year) renders
  below each poster on the library page. Default is ON — the Settings
  entry is only written when the user opts out.
  """

  alias MediaCentaur.Settings

  @setting_key "library_show_card_info"

  @spec setting_key() :: String.t()
  def setting_key, do: @setting_key

  @spec enabled?() :: boolean()
  def enabled? do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: %{"enabled" => false}}} -> false
      _ -> true
    end
  end
end
```

### `MediaCentaurWeb.Live.LibraryCardInfoAware`

Structural copy of `SpoilerFreeAware`:

* `on_mount` seeds `:show_card_info` from `LibraryCardInfo.enabled?/0`.
* Subscribes to the Settings topic via `Settings.subscribe/0` when
  `connected?/1`.
* Attaches a `handle_info` hook that re-assigns `:show_card_info` when
  `{:setting_changed, "library_show_card_info", value}` arrives, then
  returns `{:cont, socket}`.

Hosts MUST NOT call `Settings.subscribe()` themselves — same contract as
`SpoilerFreeAware`, same EntityModalContract Credo coverage.

### `LibraryCards.poster_card`

Add:

```elixir
attr :show_info, :boolean, default: true,
  doc: "When false, hides the title + type/year footer below the poster — gives a pure wall-of-posters view."
```

Wrap the existing footer `<div class="p-2">…</div>` (lines 73-81) in
`:if={@show_info}`.

### `MediaCentaurWeb.Live.LibraryLive`

* Add `use MediaCentaurWeb.Live.LibraryCardInfoAware`.
* Pass `show_info={@show_card_info}` into each `LibraryCards.poster_card`
  invocation (currently one call at `library_live.ex:406`).

### `MediaCentaurWeb.Live.SettingsLive`

* New handler:

  ```elixir
  def handle_event("toggle_show_card_info", _params, socket) do
    enabled = !socket.assigns.show_card_info

    Settings.find_or_create_entry!(%{
      key: "library_show_card_info",
      value: %{"enabled" => enabled}
    })

    {:noreply, assign(socket, show_card_info: enabled)}
  end
  ```

* `use MediaCentaurWeb.Live.LibraryCardInfoAware` on `SettingsLive` so the
  toggle's bound assign stays live.
* Render an instant-toggle control in the Library section
  (`settings_live.ex` near line 2788), styled to match the
  `toggle_spoiler_free` precedent. Label: "Show titles below posters".
  Caption: "Hide for a clean wall-of-posters view."
* Do **not** add the field to the existing `#settings-library` form — it's
  an instant toggle, not a Save-button-gated preference.

## Storybook

Add to `storybook/components/library_cards/poster_card.story.exs`:

```elixir
%Variation{
  id: :wall_of_posters,
  attributes: %{
    id: "poster-card-no-info",
    entry: <existing fixture>,
    show_info: false
  }
}
```

The existing variations stay on `show_info: true` (the attr default).

## Tests

| Test | Lives in | Asserts |
|---|---|---|
| `library_card_info_test.exs` | `test/media_centaur/` | `enabled?/0` returns `true` when entry missing; `true` for `%{"enabled" => true}`; `false` for `%{"enabled" => false}`. |
| `library_card_info_aware_test.exs` | `test/media_centaur_web/live/` | `on_mount` seeds assign from current value; broadcasting `{:setting_changed, "library_show_card_info", %{"enabled" => false}}` re-assigns. |
| `library_live_test.exs` (extension) | `test/media_centaur_web/live/` | Footer text visible by default; after `Settings.find_or_create_entry!(%{key: "library_show_card_info", value: %{"enabled" => false}})` and a `setting_changed` broadcast, footer text absent on re-render. |
| Storybook compile + render | enforced by `mix precommit` | Picks up the new variation automatically. |

## Migration / data shape

No migration needed — Settings is a sparse key/value table. Absence of the row
means "default" (on).

## Out of scope

* Migrating existing `Config.runtime_settable_keys/0` to typed accessors —
  tracked in `campaigns/runtime-prefs-out-of-toml.md`. `LibraryCardInfo` is
  the canonical example of the target pattern but does not refactor
  existing call sites.
* Per-section or per-page granularity (e.g. hide-info on the library but
  show-info on a detail strip). Single global library preference.
* Toolbar quick-toggle on the library page itself. Explicitly chose the
  Settings-page Library section instead.

## Pointers

* Pattern reference: `lib/media_centaur/spoiler_free.ex`,
  `lib/media_centaur_web/live/spoiler_free_aware.ex`.
* Existing toggle UI: `lib/media_centaur_web/live/settings_live.ex:603`
  (`toggle_spoiler_free`).
* Component: `lib/media_centaur_web/components/library_cards.ex:14-84`.
* Story: `storybook/components/library_cards/poster_card.story.exs`.
* Campaign: `campaigns/runtime-prefs-out-of-toml.md`.
