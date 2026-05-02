# Sandboxing — chrome / sandbox / theme architecture

Phoenix Storybook does **not** isolate components in iframes by default. Components render directly in the storybook page, sharing the LiveSocket and DOM with the chrome. This is fast but creates two failure modes:

1. Storybook chrome styles leak into your components.
2. Your app styles leak into storybook chrome.

This doc explains how we mitigate both, and why the CSS overrides in `assets/css/app.css` look the way they do.

## What loads where

- **Chrome** = the storybook UI: sidebar, header, tabs, search box. Tailwind classes use the `psb:` prefix and only `.psb`-classed elements get preflight reset.
- **Sandbox** = the container around each variation render. It carries `class="psb-sandbox media-centarr"` (the second is our `sandbox_class`). Components render inside this.
- **`css_path`** loads into the same DOM as chrome — the `psb:` prefix is what (mostly) prevents storybook utilities from clashing with our utilities.
- **`js_path`** loads before storybook's own JS and is where you set `window.storybook = { Hooks, Params, Uploaders }` if components need them.

## Why `:root` selectors in our CSS were a problem

Our `app.css` declares the daisyUI dark theme on `:root` with `color-scheme: dark` and a near-white `--color-base-content`. Both cascade to every element — including storybook's chrome. Symptoms:

- Storybook chrome (white panels) shows near-white text → unreadable.
- `bg-white` chrome elements pick up our dark scheme defaults.

The dual problem: chrome leaking into components, and our CSS leaking into chrome.

## How we solve it

The chrome's `<html>` and `<body>` carry the `psb` class. The sandbox carries `media-centarr`. Three rules combined:

### 1. Scope the body gradient

Originally:

```css
body { background-image: ...gradient...; }
```

Now:

```css
body.media-centarr { background-image: ...gradient...; }
```

Effect: the gradient only paints when `body` has the sandbox class. The live app body has it (we added `class="media-centarr"` in `root.html.heex`). The storybook chrome body doesn't.

### 2. Reset chrome to a light scheme

```css
html.psb {
  color-scheme: light;
}

html.psb body {
  background-color: white;
  background-image: none;
  color: oklch(20% 0.015 264);
}
```

This kicks in only inside storybook's chrome (`html.psb`). Browser defaults flip back to dark-on-light, our gradient is suppressed, body text is dark.

### 3. Restore dark theme inside component preview sandboxes

```css
html.psb .psb-variation-block .media-centarr {
  color-scheme: dark;
  color: var(--color-base-content);
  background:
    radial-gradient(ellipse at 20% 15%, var(--glass-gradient-a), transparent 60%),
    radial-gradient(ellipse at 80% 80%, var(--glass-gradient-b), transparent 60%),
    var(--color-base-100);
  border-radius: 0.375rem;
}
```

`.psb-variation-block` is only present on **component story** pages — never on `:page` story pages. So `:page` stories (welcome, future docs) stay in the chrome's light scheme; component previews get our dark theme + gradient + glass surfaces.

The selector specificity is `(0,2,2)` which beats daisyUI's `:root` rules.

## Why not `data-theme`?

daisyUI v5 supports `data-theme="name"` for scoping themes to a subtree. Two reasons we didn't go that route:

1. The live app's `<html>` doesn't currently carry `data-theme`; the dark theme applies via `prefersdark: true` + `default: true`. Refactoring app theming for the sake of storybook would break the live UI.
2. Phoenix Storybook's `sandbox_class` adds a **class**, not an attribute. There's no built-in way to set `data-theme` on sandbox containers.

Class-based scoping (above) is uglier but doesn't require app changes.

## Why not `:has()`-based selectors?

The first attempt was `html:not(:has(.media-centarr))` — assuming the chrome's `<html>` would have no `.media-centarr` descendant. That fails because storybook puts `.media-centarr` on every variation's container, and those are children of the chrome's `<html>`.

Lesson: don't reason about "chrome vs sandbox" via DOM ancestry. Use the explicit class markers (`html.psb` vs `.media-centarr` vs `.psb-variation-block`) that storybook already provides.

## Why not a separate storybook.css?

The auto-generator creates `assets/css/storybook.css` and `assets/js/storybook.js` and points `css_path`/`js_path` at them. We deleted those because:

- It doubles maintenance — every theme tweak goes in two places.
- The `psb:` prefix already isolates chrome utilities from component utilities.
- The class-scoped overrides above achieve sandbox isolation cleanly.

Rule: do **not** recreate those files. If you need component-specific behaviour, either declare it inline in `app.css` scoped to `.media-centarr`, or use a Tailwind plugin that applies inside the sandbox.

## Iframe escape hatch

`def container, do: :iframe` switches a single story to render in a real iframe. Phoenix Storybook handles two cases:

- **Function component** — uses `srcdoc` to inline the iframe HTML, no extra HTTP fetch.
- **Live component** — full iframe with a separate request to a route under `/storybook/iframe/*story` (mounted by `live_storybook/2`).

When to reach for it:

- Component installs `document`-level event listeners.
- You're testing responsive CSS behaviour at narrow widths.
- A component fundamentally clashes with chrome styling and class-scoped fixes are too invasive.

When **not** to reach for it:

- "It looks weird" — diagnose the CSS first. Almost always the issue is theme/sandbox scoping, not isolation. Iframes are slower and lose the LiveSocket sharing benefit.

## Checking your work

When something looks off, run this in the dev console with the storybook page open:

```js
const sb = document.querySelector('.media-centarr');
console.log({
  htmlClass: document.documentElement.className,
  htmlColorScheme: getComputedStyle(document.documentElement).colorScheme,
  bodyClass: document.body.className,
  bodyColor: getComputedStyle(document.body).color,
  sandboxColorScheme: sb && getComputedStyle(sb).colorScheme,
  sandboxBaseContent: sb && getComputedStyle(sb).getPropertyValue('--color-base-content').trim(),
  hasVariationBlock: !!document.querySelector('.psb-variation-block')
});
```

Expected on a component story:

```js
{
  htmlClass: "psb",
  htmlColorScheme: "light",
  bodyColor: "oklch(0.2 0.015 264)",        // dark text on light chrome
  sandboxColorScheme: "dark",                // restored inside variation block
  sandboxBaseContent: "oklch(93% 0.005 264)",// daisyUI dark var
  hasVariationBlock: true
}
```

Expected on a `:page` story (welcome):

```js
{
  htmlClass: "psb",
  htmlColorScheme: "light",
  bodyColor: "oklch(0.2 0.015 264)",
  sandboxColorScheme: "light",               // page sandbox stays light
  hasVariationBlock: false
}
```

If `htmlColorScheme` is `"dark"`, the `html.psb` reset isn't winning specificity. If `sandboxColorScheme` is `"light"` on a component story, the `.psb-variation-block .media-centarr` rule isn't matching.

## Color modes (currently unused)

Phoenix Storybook has built-in light/dark/system support via `color_mode: true`. We don't enable it because our app is dark-only — the dark theme is the only theme. If we ever ship a light theme, revisit:

1. Set `color_mode: true` in `lib/media_centarr_web/storybook.ex`.
2. Set `color_mode_sandbox_dark_class: "dark-theme"` (or whatever class triggers our dark theme).
3. Update the override rules to switch theme based on the sandbox class instead of unconditionally restoring dark.

Until then, keep `color_mode` off.

## Testing

Phoenix Storybook ships dedicated chrome-less endpoints for visual regression tooling:

- `/storybook/visual_tests/<area>/<story>` — single story without chrome
- `/storybook/visual_tests?start=a&end=e` — range, alphabetical

If we wire up Percy/Argos/etc. for visual diffs, hit those URLs. Currently unused.
