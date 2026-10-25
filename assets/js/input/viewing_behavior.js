/**
 * The viewing layer's keys — a remote player's OSD is the host's page
 * (campaigns/remote-players.md, M5), so while a viewing is on the page's
 * keys become playback commands the host sends down the player channel.
 *
 * `withViewing` is a decorator applied by `page_behavior.js` whenever the
 * reader sees `[data-viewing]`; it is detached with the layer. In the bar
 * state (no track menu open) it turns actions into `viewing_command`
 * pushes: arrows seek (±10 s sideways, ±60 s up and down), SELECT acts on
 * the prompt while one shows (the desktop rule: ENTER is the pill's while
 * the pill is up) and toggles pause otherwise, the remote's media keys
 * play/pause and seek 30 s, and MENU opens the track menu. Paused, the bar
 * shows an "Audio & subtitles" button — the track menu on a remote without a
 * Menu key: DOWN focuses it, SELECT on it opens the menu, UP leaves it, and
 * LEFT and RIGHT still seek. BACK passes through: containment dismisses the
 * overlay, whose dismiss event stops the viewing. With the menu open the
 * decorator steps aside so MODAL navigation walks the lists, except that
 * MENU closes it. Zone cycling and CLEAR mean nothing during a viewing.
 */

import { Action } from "./core/index.js"

const BAR_SEEKS = Object.freeze({
  [Action.NAVIGATE_LEFT]: -10,
  [Action.NAVIGATE_RIGHT]: 10,
  [Action.NAVIGATE_UP]: 60,
  [Action.NAVIGATE_DOWN]: -60,
  [Action.SEEK_FORWARD]: 30,
  [Action.SEEK_BACK]: -30,
})

const SWALLOWED = new Set([Action.ZONE_NEXT, Action.ZONE_PREV, Action.CLEAR])

/**
 * Wrap a page behavior for the time a viewing is on.
 *
 * @param {import("./page_behavior").PageBehavior} behavior - the page's own behavior ({} when it has none)
 * @param {{pushEvent: function(string, Object): void, isMenuOpen: function(): boolean, hasPrompt: function(): boolean,
 *   hasTracksButton: function(): boolean, isTracksFocused: function(): boolean,
 *   focusTracksButton: function(): void, leaveTracksButton: function(): void}} deps
 * @returns {import("./page_behavior").PageBehavior}
 */
export function withViewing(behavior, deps) {
  const command = (payload) => deps.pushEvent("viewing_command", payload)

  return {
    ...behavior,
    onAction(action, context, focused) {
      if (deps.isMenuOpen()) {
        if (action === Action.MENU) {
          deps.pushEvent("viewing_menu_close", {})
          return true
        }
        return behavior.onAction?.(action, context, focused) ?? false
      }

      // The tracks button is outside the nav system (as a nav item it would
      // take the cursor the moment a pause renders it, and the next OK would
      // open the menu instead of resuming), so its focus is asked, not read.
      const onTracks = deps.isTracksFocused()
      if (onTracks && action === Action.SELECT) {
        deps.pushEvent("viewing_menu_open", {})
        return true
      }
      if (onTracks && action === Action.NAVIGATE_UP) {
        deps.leaveTracksButton()
        return true
      }
      if (action === Action.NAVIGATE_DOWN && (onTracks || deps.hasTracksButton())) {
        if (!onTracks) deps.focusTracksButton()
        return true
      }

      if (action in BAR_SEEKS) {
        command({ command: "seek", seconds: BAR_SEEKS[action] })
        return true
      }

      switch (action) {
        case Action.SELECT:
          if (deps.hasPrompt()) deps.pushEvent("viewing_prompt", {})
          else command({ command: "toggle_pause" })
          return true
        case Action.PLAY_PAUSE:
        case Action.PLAY:
          command({ command: "toggle_pause" })
          return true
        case Action.MENU:
          deps.pushEvent("viewing_menu_open", {})
          return true
        case Action.BACK:
          return false
        default:
          return SWALLOWED.has(action)
      }
    },
  }
}
