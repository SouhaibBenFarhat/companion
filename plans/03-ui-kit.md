Every OKLCH value below is computed and verified — the token test in section 6 passes on the proposed set and fails on today's file.

---

# Companion UI (user interface) kit — specification

Target: `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src`. One window, 460 points wide, one theme family, one platform. The kit is sized for that and nothing larger.

---

## 1. Layers

Four layers. Each one has a test you can answer in a second.

| Layer | Lives in | Test |
|---|---|---|
| **Tokens** | `ui/tokens.css` | Would a second theme change this value while the name stayed the same? Yes → token. |
| **Base rules** | `ui/base.css` | Does every interactive element need it, whatever it is? Focus, disabled, hover, cursor, scrollbar → base. |
| **Components** | `ui/*.tsx` | Could you delete every file in `components/` and this file still make sense? Yes → component. |
| **Views** | `components/*.tsx` | Does it know what Companion is — repos, agents, permissions, messages? Yes → view. |

Rules that follow from the table:

- A **token** is the only place a colour, size, radius, duration or z-index number may be written.
- A **base rule** is the only place `:focus-visible`, `:hover`, `:active` and `:disabled` are styled. A component never writes them.
- A **component** reads tokens and knows nothing about Companion. No repo names, no agent ids, no `send()`.
- A **view** contains no styling at all. It arranges components and holds state.

Three layers from the research are deliberately **not** built:

- **No raw/semantic/component three-tier token split.** Two tiers: ramps (`--s-*`, `--t-*`, `--b-*`, `--a-*`, `--d-*`) and roles (`--c-*`). One theme family does not earn a third.
- **No patterns layer.** With this few components a "pattern" would just be a view.
- **No headless primitive layer of our own.** Where behaviour is hard, we take Radix (section 3). Where it is easy, the component owns it.

---

## 2. Tokens

### 2.1 The structural fix

The reported bug: `--c-overlay` and `--c-control-hover` were both `oklch(31% …)`. Two independent numbers that happened to meet.

The research offers two fixes. **We take the relative transform of the surface, not a hover token per surface.**

Why: a hover token per surface fixes today's collision and guarantees tomorrow's. The count grows by multiplication (surfaces × states), and every new surface starts with no hover, so somebody reuses the nearest one. A relative transform makes the collision arithmetically impossible — hover is *defined* as "one step away from where I sit", so it can never equal its own surface, and a new surface gets its states for free.

Three things must be true for it to work, and all three hold here:

1. **The step is signed.** Light mode goes darker, dark mode goes lighter. `calc(l + 0.05)` on a white card clamps at 1 and produces nothing. One `--state-step` token, redeclared per appearance.
2. **Alpha carries through.** `oklch(from var(--surface) calc(l + …) c h)` with the alpha slot left out keeps the origin colour's alpha. That is why the hover keeps showing the blurred AppKit material behind the panel — today's `--c-overlay-hover` is fully opaque and stops showing it.
3. **The browser supports it.** Relative colour syntax is Safari 16.4 and up. The panel's web view is Safari 17 or newer.

Not `color-mix()`: it moves toward a second colour, so the same mix reads clearly on a mid-grey card and barely at all on a near-white one. Not an opacity wash: it needs an extra pseudo-element, it fights `border-radius`, and 6% white is invisible on a white card.

### 2.2 Ramps (tier 1)

Three small ramps, not one 12-step scale. This app's light mode raises surfaces toward white and then drops text to near-black, so a single monotonic list cannot cover both. Every step is an index. **No file outside `ui/tokens.css` may read a ramp variable.**

**Surface ramp** — index is height above the panel floor. Hue 285 throughout.

| Step | Dark | Light | Used by |
|---|---|---|---|
| `--s-1` | `12.5% 0.010` | `93.5% 0.006` | well, input |
| `--s-2` | `15% 0.011` | `95.5% 0.005` | code |
| `--s-3` | `19.5% 0.012` | `97.5% 0.004` | chrome |
| `--s-4` | `23% 0.013` | `100% 0` | control |
| `--s-5` | `26.5% 0.015` | `100% 0` | card |
| `--s-6` | `30% 0.017` | `100% 0` | overlay |

**Ink ramp** — index is contrast against the surfaces, rising.

| Step | Dark | Light | Used by | Floor |
|---|---|---|---|---|
| `--t-1` | `66% 0.014` | `74% 0.014` | faint — disabled and unavailable text only | Lc 28 |
| `--t-2` | `84% 0.012` | `52% 0.020` | muted — secondary text | Lc 60 |
| `--t-3` | `94% 0.004` | `25% 0.020` | ink — body text | Lc 75 |

`Lc` is the score from APCA (Accessible Perceptual Contrast Algorithm). Dark `--t-2` moves from today's 69% to 84%: at 69% it scores Lc 37.5 on a dark menu, far under the Lc 60 needed to read small text.

**Border pair.**

| Step | Dark | Light | Used by |
|---|---|---|---|
| `--b-1` | `34% 0.018` | `88% 0.008` | hairline between bars, around a card |
| `--b-2` | `50% 0.020` | `79% 0.012` | outline of a floating surface, border of an input, toggle track |

Dark `--b-1` moves from 32% to 34%: at 32% a divider inside a 31% menu is invisible.

**Accent and danger.** Both split into fill, text and soft, because a colour readable as text is too dark to fill a button, and the reverse.

| Token | Dark | Light |
|---|---|---|
| `--a-fill` | `58% 0.19 285` | `55% 0.19 285` |
| `--a-fill-hover` | `63% 0.18 285` | `49% 0.19 285` |
| `--a-text` | `84% 0.08 285` | `46% 0.19 285` |
| `--a-soft` | `31% 0.055 285` | `93% 0.035 285` |
| `--d-fill` | `55% 0.18 25` | `52% 0.19 25` |
| `--d-text` | `85% 0.08 25` | `50% 0.19 25` |
| `--d-soft` | `32% 0.055 25` | `93% 0.035 25` |
| `--on-fill` | `99% 0 285` | `99% 0 285` |

Dark `--a-text` drops chroma from 0.13 to 0.08 and raises lightness from 78% to 84%. At 78%/0.13 it scored Lc 51.1 on a menu — unreadable as a link — and 84%/0.13 is outside the sRGB gamut, so the chroma has to come down with it. Same reasoning for `--d-text`.

**Alpha.** Surfaces stay see-through so the AppKit blur shows. Alpha is its own tier‑1 value so the role block below is written once and never repeated per appearance.

| Token | Dark | Light |
|---|---|---|
| `--alpha-well` | `0.62` | `0.74` |
| `--alpha-chrome` | `0.74` | `0.84` |
| `--alpha-card` | `0.94` | `0.96` |
| `--alpha-overlay` | `0.985` | `0.985` |
| `--alpha-input` | `0.90` | `0.96` |

**Non-colour scales.** Same tier, same rule — nothing outside the token file writes these numbers.

```
--h-xs: 24px;   --h-sm: 28px;   --h-md: 32px;
--text-2xs: 10px; --text-xs: 11px; --text-sm: 12px; --text-md: 13px;
--radius-sm: 6px; --radius-md: 8px; --radius-lg: 12px;
--icon-size: 14px; --icon-stroke: 1.75;
--focus-w: 2px; --focus-off: 2px;
--z-float: 50;
--dur-state: 120ms; --dur-move: 150ms;
```

Radius nesting rule: a child's radius is the parent's radius minus the parent's padding. A menu is `--radius-lg` (12) with 4 padding, so its rows are `--radius-md` (8). A composer well is 12 with 10 padding, so its buttons are `--radius-md` (8). This is why Send stops being `--radius-sm`.

Height rule: one scale, used by everything. `xs` 24, `sm` 28, `md` 32. `Button size="sm"` and `IconButton size="sm"` are both 28. Today they are 28 and 24, which is why a composer row is 4 pixels out of line.

### 2.3 Roles (tier 2)

Written once, at `:root`, never repeated in the dark block. This is the layer views and components read.

```css
:root {
  --c-well:    oklch(from var(--s-1) l c h / var(--alpha-well));
  --c-input:   oklch(from var(--s-1) l c h / var(--alpha-input));
  --c-code:    var(--s-2);
  --c-chrome:  oklch(from var(--s-3) l c h / var(--alpha-chrome));
  --c-control: var(--s-4);
  --c-card:    oklch(from var(--s-5) l c h / var(--alpha-card));
  --c-overlay: oklch(from var(--s-6) l c h / var(--alpha-overlay));

  --c-faint: var(--t-1);
  --c-muted: var(--t-2);
  --c-ink:   var(--t-3);

  --c-line:        var(--b-1);
  --c-line-strong: var(--b-2);
  --c-track:       var(--b-2);   /* toggle, off */
  --c-handle:      var(--b-2);   /* the drag grip */

  --c-accent:       var(--a-fill);
  --c-accent-hover: var(--a-fill-hover);
  --c-accent-text:  var(--a-text);
  --c-accent-soft:  var(--a-soft);
  --c-accent-fg:    var(--on-fill);

  --c-danger:      var(--d-fill);
  --c-danger-text: var(--d-text);
  --c-danger-soft: var(--d-soft);
  --c-danger-fg:   var(--on-fill);

  --c-focus: oklch(from var(--a-fill) l c h / 0.55);
  --c-knob:  var(--on-fill);
}
```

Every surface has a paired foreground: `card`/`ink`, `overlay`/`ink`, `accent`/`accent-fg`, `accent-soft`/`accent-text`, `danger`/`danger-fg`, `danger-soft`/`danger-text`. The test in section 6 asserts each pair.

**Deleted tokens**, all of them replaced by the derivation below: `--c-overlay-hover`, `--c-overlay-active`, `--c-control-hover`, `--c-control-active`, `--c-input-focus`. The last one goes because the focus signal is now the one shared outline, not a background change.

**New tokens** that existed only as raw values: `--c-faint` (was `text-muted/60` and `opacity-45`), `--c-accent-soft` (was `bg-accent/12`, three call sites), `--c-danger-text` (was `--c-danger` doing two jobs), `--c-danger-fg` (was `text-white`), `--c-knob` (was `bg-white`), `--c-track`, `--c-handle` (was `bg-muted/30`).

### 2.4 States, derived

```css
:root { --state-step: -0.035; }                              /* light: darker */
@media (prefers-color-scheme: dark) { :root { --state-step: 0.05; } }  /* dark: lighter */

[data-surface] {
  --surface:        var(--c-card);
  --state-hover:    oklch(from var(--surface) calc(l + var(--state-step)) c h);
  --state-active:   oklch(from var(--surface) calc(l + var(--state-step) * 1.8) c h);
  --state-divider:  oklch(from var(--surface) calc(l + var(--state-step) * 2.4) c h / 1);
}
[data-surface="well"]    { --surface: var(--c-well); }
[data-surface="chrome"]  { --surface: var(--c-chrome); }
[data-surface="card"]    { --surface: var(--c-card); }
[data-surface="overlay"] { --surface: var(--c-overlay); }
[data-surface="input"]   { --surface: var(--c-input); }
```

A row inside a menu now takes its hover from the menu. A row inside a card takes it from the card. Neither can be wrong, and neither can be forgotten. `--state-divider` forces alpha 1 so a separator stays solid on a see-through menu.

### 2.5 Base rules

One focus treatment, one disabled treatment, one hover treatment, for everything.

```css
@layer base {
  /* Focus: an outline, not a ring. An outline needs no offset colour, so the
     ring-offset-chrome halo on every non-chrome surface disappears. */
  :where(a, button, input, textarea, select, [tabindex]):focus-visible {
    outline: var(--focus-w) solid var(--c-focus);
    outline-offset: var(--focus-off);
  }
  /* A well draws the focus around itself, not around the bare textarea inside. */
  [data-focus="within"]:has(:focus-visible) {
    outline: var(--focus-w) solid var(--c-focus);
    outline-offset: var(--focus-off);
  }
  [data-focus="within"] :focus-visible { outline: none; }

  /* Pressable: hover, press, and the open state of a menu trigger. */
  [data-pressable] { transition: background-color var(--dur-state), color var(--dur-state); }
  :where([data-pressable]):hover,
  :where([data-pressable])[data-highlighted]        { background-color: var(--state-hover); }
  :where([data-pressable]):active,
  :where([data-pressable])[data-state="open"]       { background-color: var(--state-active); }

  /* Disabled: a token colour, never opacity. Opacity destroys contrast and
     stacks when a call site adds its own. */
  :where(:disabled, [data-disabled]) {
    color: var(--c-faint);
    background-color: transparent;
    pointer-events: none;
    cursor: not-allowed;
  }
  /* Unavailable is not disabled: the user can fix it, so it stays clickable. */
  [data-unavailable] { color: var(--c-faint); }

  button:not(:disabled) { cursor: pointer; }
}
```

Menu rows are styled by `[data-highlighted]` only, never by `:hover`. Radix sets that attribute for both the mouse and the arrow keys, so there is one highlight instead of two at once. Menu rows do not get a focus outline — the highlight already carries the state, and both together read as two selections.

### 2.6 Tailwind bridge

`@theme inline` stays exactly as it is, with the `--color-*` names updated to match the role list. Keep `inline`: without it a theme variable resolves once at `:root` and a nested override never reaches it. The advice going round to drop it is backwards.

### 2.7 The macOS accent colour — not now

The panel could read `NSColor.controlAccentColor` in Swift and inject it. Not in this version: the eight system accent hues have very different luminance at the same OKLCH lightness, so every contrast promise in the table above would have to be re-checked per hue at build time. Revisit only with that check written first.

---

## 3. Primitives — build or adopt

Install one package: **`radix-ui`** (single package, version 1.6.7), not the separate `@radix-ui/react-*` packages. One version number means one copy of `dismissable-layer`, which is the usual root cause of the stuck `pointer-events: none` failure. Measured cost for both components used below: about 30 kilobytes gzipped. Base UI costs about 48 kilobytes for the same two, so Radix wins here on size alone.

```ts
import { DropdownMenu, Popover } from 'radix-ui'
```

| Primitive | Decision | Why |
|---|---|---|
| **Menu** | Radix `DropdownMenu` | Arrow keys, Home/End, typeahead, roving tabindex, `role="menu"`/`menuitem`/`menuitemradio`, `aria-haspopup`/`expanded`, focus return. `AgentMenu.tsx` has a `role="menu"` with none of it; `HistoryMenu.tsx` has no keyboard story at all. This was hand-rolled twice and is wrong twice. |
| **Popover** | Radix `Popover` | Shares seven internal packages with `DropdownMenu`, so it costs under 1 kilobyte more. Solves the confirm popover in `ComposerControls.tsx:87-122`, which today cannot be dismissed by clicking away or by Escape. |
| **Tooltip** | **Neither — use the native `title` attribute** | `IconButton` already requires a `label` and passes it to `title`. The macOS tooltip is real, free, delayed correctly, and is one fewer floating surface to dismiss in a panel where dismissal is the thing that keeps breaking. Do not add Radix Tooltip. |
| **Select** | Hand-built wrapper over native `<select>` | The system popup scrolls, does typeahead, and costs nothing. Radix Select is the largest component in the set. Keep `ui/Input.tsx`'s current approach. |
| **Dialog** | Not built | Nothing in the app is modal. The confirm is anchored to its trigger, so it is a Popover. `SettingsSheet` is a view swap, not a dialog. |
| **Switch** | Hand-built (`ui/Toggle.tsx`) | A `<button role="switch">` already gets Space and Enter from the platform. Nothing to gain. |
| **Row / list** | Hand-built (`ui/ListRow.tsx`) | Rebuilt three times today. It is layout plus one `data-pressable` attribute. Inside a Menu it renders as `Menu.Item`. |
| **DragRegion** | Hand-built (`ui/DragRegion.tsx`) | `-webkit-app-region: drag` does nothing in this web view, so `startDrag` is spread across eight call sites in two files. |

Four settings are **required** on every Radix surface in this app. They are not optional and not preferences:

1. `modal={false}` on `DropdownMenu.Root` and `Popover.Root`. Modal mode writes `document.body.style.pointerEvents = 'none'` and restores it from a single module-level variable. Two overlapping layers and the page goes permanently dead to clicks. In a browser you press Cmd+R; here the panel is borderless with no address bar, so the user has to quit the app. There is nothing to gain either — `body` is already `overflow: hidden`, so there is no page scroll to lock.
2. `onEscapeKeyDown={(e) => e.stopPropagation()}` on every `Content`. `App.tsx:113` listens for Escape on `window` in the bubble phase; Radix listens on `document` in the capture phase. Without this, one Escape closes the menu **and** hides the whole panel.
3. `collisionPadding={8}` plus `max-height: var(--radix-dropdown-menu-content-available-height)` and `overflow-y: auto` on `Content`. Radix only knows the rectangular viewport. The visible rounded corner is an AppKit mask (`PanelController.swift:92-94`, radius 12) that Radix cannot see, and the panel resizes down to 320×240, where a history list runs off the bottom.
4. `onCloseAutoFocus={(e) => { e.preventDefault(); focusComposer() }}`. Returning focus to a small chevron button is wrong in a chat panel.

Two things Radix cannot do, which the kit must:

- **Close on window blur.** The panel is a nonactivating `NSPanel`. Clicking another app sends no `pointerdown` to the document, so `onPointerDownOutside` never fires and the menu stays open — the same latch bug already fixed once in the island repo. `ui/Menu.tsx` and `ui/Popover.tsx` each add `window.addEventListener('blur', close)` while open.
- **Set `z-index` on `Content`, never on the wrapper.** Radix inserts an undocumented `<div data-radix-popper-content-wrapper>` you cannot put a class on, and it copies the computed `z-index` from your `Content` at mount. Use `--z-float`.

Always use `<Portal>` with the default `document.body` container. Every token lives on `:root` and dark mode switches with a media query, not a class, so a portalled menu keeps the whole theme with no extra work. Do not set `container` to a node inside `#root` — that is the most common way to break Radix positioning in an embedded view, because any ancestor that later gains `transform`, `filter`, `backdrop-filter`, `will-change` or `contain` becomes the containing block for Radix's fixed-position wrapper.

---

## 4. Components

**No kit component accepts `className`.** The prop type omits it, so passing one is a compile error. That removes the class-merge problem entirely: in a stylesheet the source order decides the winner, not the order of names in the class attribute, so a passed-in override silently does nothing today. Where a view needs spacing, it wraps in its own plain `<div>`. Where it needs a look, that look is a variant.

Variants are a data table in `ui/variants.ts`, and every variant union is closed. A prop typed `string` lets a typo compile and ship.

### `ui/Surface.tsx`

```tsx
Surface({ level, radius, padding, children }: {
  level: 'well' | 'chrome' | 'card' | 'overlay' | 'input' | 'code'
  radius?: 'sm' | 'md' | 'lg'            // default 'lg'
  padding?: 0 | 1 | 2 | 3                // 0, 4, 8, 12
  children: React.ReactNode
})
```
Sets `data-surface={level}`, so everything inside it derives its own states. `overlay` also gets `border: 1px solid var(--c-line-strong)`. Never a drop shadow.

```tsx
Bar({ edge, padding, children })          // edge: 'top' | 'bottom'
Sheet({ children, action })               // scrolling body + a floating action row
Divider()                                 // 1px, var(--state-divider)
```
`Bar` keeps `edge` — with two positions and a different hairline for each, it is a real variant. `Sheet` absorbs `SettingsSheet.tsx:59` and `:180-186`.

### `ui/Button.tsx`

```tsx
Button({ variant, size, tone, full, disabled, children, ...button }: {
  variant?: 'filled' | 'outlined' | 'ghost'    // default 'outlined'
  tone?: 'accent' | 'neutral' | 'danger'       // default 'accent' for filled, 'neutral' otherwise
  size?: 'xs' | 'sm' | 'md'                    // 24 / 28 / 32, default 'sm'
  full?: boolean
})
```
`variant` × `tone` replaces today's flat four-name list and gives the filled danger button that `ComposerControls.tsx:110-119` hand-built with raw `text-white` and an opacity hover. Radius is always `--radius-md`. Text size follows height: xs → `--text-xs`, sm → `--text-sm`, md → `--text-md`.

### `ui/IconButton.tsx`

```tsx
IconButton({ label, size, tone, pressed, unavailable, badge, disabled, children, ...button }: {
  label: string                                 // required; becomes aria-label and title
  size?: 'xs' | 'sm' | 'md'                     // same scale as Button
  tone?: 'neutral' | 'accent' | 'danger'
  pressed?: boolean                             // sets aria-pressed and the soft accent fill
  unavailable?: boolean                         // data-unavailable: dim but still clickable
  badge?: boolean                               // the small corner dot
})
```
`pressed`, `unavailable` and `badge` are the three states that forced `ComposerControls.tsx` to fork `IconButton` twice (lines 140-148 and 177-186) and `Composer.tsx:82` to repaint one as a primary button.

### `ui/Pill.tsx`

```tsx
Pill({ tone, pressed, unavailable, icon, children, ...button }: {
  tone?: 'neutral' | 'accent' | 'danger'
  pressed?: boolean
  unavailable?: boolean
  icon?: React.ReactNode
})
```
Fixed height `--h-sm`, radius `--radius-sm`, text `--text-sm`. This is the composer control shape, written three times today with three different gaps (`ComposerControls.tsx:67-76`, `ComposerControls.tsx:100-119`, `AgentMenu.tsx:81-86`).

### `ui/Menu.tsx` — compound, wraps Radix

```tsx
Menu.Root({ open, onOpenChange, children })
Menu.Trigger({ children })                       // asChild onto a Pill or IconButton
Menu.Content({ side, align, width, children })   // portal, modal=false, the four required settings
Menu.Item({ onSelect, disabled, children })
Menu.RadioGroup({ value, onValueChange, children })
Menu.RadioItem({ value, children })              // renders the check slot itself
Menu.Label({ children })
Menu.Separator()
```
`width`: `'trigger' | 'auto' | number`. Anatomy: `Root > Trigger + Content > (Label | Item | RadioGroup > RadioItem | Separator)*`.

### `ui/Popover.tsx` — compound, wraps Radix

```tsx
Popover.Root({ open, onOpenChange, children })
Popover.Trigger({ children })
Popover.Content({ side, align, width, selectable, children })
```
`selectable` adds the `.selectable` class, because `body` sets `user-select: none` and a portalled popover holding copyable text needs it back.

### `ui/ListRow.tsx`

```tsx
ListRow({ selected, leading, trailing, title, detail, tone, onClick }: {
  selected?: boolean
  leading?: React.ReactNode
  trailing?: React.ReactNode                     // revealed on row hover
  title: React.ReactNode
  detail?: React.ReactNode
  tone?: 'neutral' | 'danger'                    // colours `detail` only
})
```
Sets `data-pressable`. Radius `--radius-md`. Replaces the two row implementations in `AgentMenu.tsx:113` and `HistoryMenu.tsx:34-59`.

### `ui/Input.tsx`

```tsx
Input({ size, invalid, ...input })
Textarea({ size, autoGrow, minHeight, maxHeight, ...textarea })
Select({ size, children, ...select })
```
`Textarea` absorbs the auto-grow logic from `Composer.tsx:28-33`, so the main input of the app stops being a raw `<textarea>` with `outline-none` and no focus ring.

### `ui/Field.tsx`

```tsx
Field({ label, hint, htmlFor, layout, children }: {
  layout?: 'stack' | 'row'                       // default 'stack'
})
```
`row` is what the two `Toggle` rows in `SettingsSheet.tsx:141` and `:150` need; today they sit outside `Field` and break the form's one spacing rule. `Field` imports `Hint`; it does not retype its classes.

### `ui/Toggle.tsx`

```tsx
Toggle({ id, checked, onChange, label, hint, disabled })
```
Takes an `id` so `Field`'s `htmlFor` can reach it. Label size is `--text-sm` always — it no longer changes because a `hint` was passed. Knob is `--c-knob`, track off is `--c-track`, track on is `--c-accent`.

### `ui/Dot.tsx`

```tsx
Dot({ tone, pulse, size }: {
  tone: 'accent' | 'danger' | 'neutral' | 'faint'
  pulse?: boolean
  size?: 'sm' | 'md'
})
```
Replaces five separate definitions: `ui/Feedback.tsx:5`, `AgentMenu.tsx:90`, `ComposerControls.tsx:161`, `AwarenessBar.tsx:70`, `Permissions.tsx:10`.

### `ui/Text.tsx`

```tsx
Eyebrow({ tone, children })      // uppercase section label: --text-2xs, 600, tracking .08em
Hint({ children })               // --text-xs, muted
Label({ children })              // --text-sm, 500, ink
```
`Eyebrow` replaces three different specs: `SettingsSheet.tsx:16`, `MessageList.tsx:103`, `AwarenessBar.tsx:14`.

### `ui/Notice.tsx`

```tsx
Notice({ tone, title, action, children }: {
  tone?: 'muted' | 'danger'
  title?: string
  action?: React.ReactNode
})
```
The `action` slot removes the hand-placed `Button` inside a `Notice` at `MessageList.tsx:120-136`.

### `ui/Meter.tsx`

```tsx
Meter({ label, value, active })   // value 0..1, already shaped by the caller
```
Absorbs `AwarenessBar.tsx:6-24`. The cube-root shaping stays in the view — it is about speech, not about drawing.

### `ui/Bubble.tsx`

```tsx
Bubble({ children })              // the user's own message: accent fill, accent-fg text
```
Absorbs `MessageList.tsx:15-23`, the one surface in the app that was not a `Surface`.

### `ui/DragRegion.tsx`

```tsx
DragRegion({ grip, children })    // grip?: boolean — draws the pill handle
```
Owns `startDrag` and the grab cursor. Interactive children inside it call `event.stopPropagation()` on pointer down, so they never start a drag and keep a plain `onClick`. That fixes the whole header being dead to the keyboard: `Header.tsx:59, 69, 76, 84, 89` have no `onClick` at all, so Tab plus Enter does nothing today.

### `ui/Empty.tsx`

```tsx
Empty({ children })               // centred muted text on the well
```
Absorbs `App.tsx:118` and `MessageList.tsx:88`.

### `ui/Icon.tsx`

```tsx
Icon({ as, size })                // as: one of the named exports; size: 'sm' | 'md'
```
Size and stroke come from tokens, not from a number typed at the call site. Today the constants exist and five files ignore them, producing four sizes and four stroke weights for the same icons.

### Files deleted or absorbed

| File | What happens |
|---|---|
| `ui/styles.ts` | Deleted. `cx` moves to `ui/cx.ts`; the class fragments become base rules and the variant table. |
| `ui/Feedback.tsx` | Deleted. `Pulse` → `<Dot tone="accent" pulse />`. `Hint` → `ui/Text.tsx`. `Notice` → `ui/Notice.tsx`. |
| `components/AgentMenu.tsx` | Keeps its content and its `send()` calls. Loses the dismissal effect (lines 40-58), the trigger's class string, both row class strings and the hand-written divider. Becomes about 60 lines. |
| `components/HistoryMenu.tsx` | Loses the backdrop `<div>` (line 18), the `top-12` magic number and the row implementation. Becomes `Menu.Content` plus `ListRow`. |
| `components/ComposerControls.tsx` | Loses two forked `IconButton`s, three bespoke buttons and the un-dismissable confirm. |
| `components/Composer.tsx` | Loses the bespoke well, the raw `<textarea>` and the repainted Send button. |
| `components/Header.tsx` | Loses the empty `<div aria-hidden>` at line 33 (paints nothing, catches nothing) and the duplicated comment above it. Gains real `onClick` handlers. |
| `components/AwarenessBar.tsx` | Loses `Meter`, and `StartListening` (lines 109-121) is deleted — nothing imports it. |
| `components/Permissions.tsx` | Loses its local `Dot`. |
| `components/SettingsSheet.tsx` | Loses `Group` (becomes `Eyebrow` in a `<section>`) and the floating action bar (becomes `Sheet`). |
| **New** `lib/settings.ts` | `updateSettings(current, patch)` builds the whole payload. Today it is spread by hand in four places and three of them drop `microphoneDeviceUID` and `hideFromScreenShare` — so toggling Speak up, changing permission, or switching agent silently resets the microphone choice and the hide-from-screen-share setting. This is a data-loss bug, not a style one. |

---

## 5. Composition

**Compound components, with `asChild` as the single escape hatch, and `asChild` is allowed only inside `ui/`.**

Why compound: anything with more than one part has shared state — open, selected, highlighted — that must live in one place. Parts read it from context, so a view can add a separator, reorder, or swap the trigger without new props. The alternative shape, one component taking `items={[…]}` plus a render callback, breaks the first time somebody needs a part you did not predict.

Why `asChild` and not a `render` prop: we adopt Radix, and Radix ships `asChild`. Shipping both means two prop-merge orders and nobody remembers which applies where. The research prefers `render` for new kits; that is a reason to prefer Base UI, and we chose Radix on size, so we take its escape hatch and use it consistently.

Why `asChild` is confined to `ui/`: it clones a child and merges props invisibly, and swapping a `<button>` for a `<div>` silently removes keyboard activation and the button role with no warning. Inside `ui/` there are exactly three uses — `Menu.Trigger`, `Popover.Trigger`, and `Menu.Item` when a row needs to be a link — and each is reviewed once. Views never touch it.

Everything else is plain props with closed unions. No render callbacks, no `children` as a function, no `component=` prop.

Anatomy is written down for every multi-part component, next to it, as a comment block listing the parts and their required nesting. That is the thing that stops people forking a component instead of composing it.

---

## 6. Rules that keep it honest

Five rules. Each has a mechanism, not a habit.

### Rule 1 — No raw values outside `ui/tokens.css`

Enforced two ways.

Stylesheets: `stylelint` with `scale-unlimited/declaration-strict-value` on `color`, `background-color`, `border-color`, `outline-color`, `fill`, `font-size`, `border-radius`. Fails the build on a literal.

React files: an ESLint `no-restricted-syntax` rule over JSX string literals, banning
- arbitrary Tailwind values — `/-\[(#|\d|oklch|rgb|hsl)/` — which catches `text-[13px]`, `bg-[#2b2b2b]`, `w-[70%]`, `top-12` is allowed but `max-h-[62%]` is not;
- opacity modifiers on colour utilities — `/(bg|text|border|ring|fill)-[a-z-]+\/\d/` — which catches `bg-accent/12`, `text-muted/60`, `bg-muted/30`, `hover:bg-accent/20`;
- `opacity-` on anything, since disabled is a colour now.

### Rule 2 — Views may not build controls

ESLint `react/forbid-elements` in `components/`: `button`, `input`, `textarea`, `select`, `label`, `hr`. There are eleven hand-written `<button>` elements today. After this there are zero.

### Rule 3 — Views may not own floating behaviour

ESLint `no-restricted-syntax` in `components/` bans:
- `document.addEventListener` and `window.addEventListener` — dismissal and Escape belong to `Menu`, `Popover` and `App`, nowhere else;
- any `z-` class — only `Menu.Content` and `Popover.Content` set a stacking level, from `--z-float`;
- `position: fixed` / `absolute` class strings — anchoring is the primitive's job.

### Rule 4 — No `className` on kit components

Enforced by the type system, not by lint. Every kit prop type is `Omit<…, 'className'>`. Passing one does not compile. `npm run build` already runs `tsc --noEmit`, so this is free.

### Rule 5 — Tokens are tested, and the test is arithmetic

`web/tokens.test.mjs`, run by `npm test` and in the existing GitHub Actions workflow. It parses `ui/tokens.css`, pulls the lightness, chroma and hue out of every `oklch()`, and asserts three things. No browser, no screenshots.

1. **Every pair that can touch is far enough apart.** Distance is Euclidean in OKLab, floor `0.025` — for two neutrals that is exactly 2.5 lightness points, which is what a real ramp step measures in the Radix grey scales. Generated as a cross product from a `CAN_TOUCH` map, not a hand-written pair list, so a new token is covered the day it is added. Derived hover, active and divider values are generated from `--state-step` and included. Deliberate matches go in a named `EXEMPT` set with a one-line reason:
   ```
   light card/overlay      — both pure white; separated by the strong border
   light card/control      — a white button on a white card is the macOS look
   light overlay/control   — same
   light well/input        — an input never sits on the well
   ```
2. **Every text role clears its floor on every surface it can land on, at rest and on hover.** Score is APCA (Accessible Perceptual Contrast Algorithm) `Lc`. Floors: ink 75, muted 60, accent-text 60, danger-text 60, faint 28. The pressed state is not checked — it lasts as long as the mouse button is down, and asserting it would force the whole ink ramp brighter for no reading benefit.
3. **Every colour is inside the sRGB gamut.** This is what catches a dark accent-text at 84% lightness and 0.12 chroma, which looks fine in the file and clips on screen.

Do **not** use APCA for surface-against-surface. It clips low contrast to zero on purpose, so it reports `Lc 0.0` for the reported bug and for a healthy 7-point step alike — it cannot tell them apart. Do not use the WCAG (Web Content Accessibility Guidelines) 2 ratio there either: every dark surface pair in this file lands between 1.01 and 1.32, too compressed for any threshold to mean anything. Lightness distance for surfaces, APCA for text. Two metrics, two jobs.

Run against **today's** `index.css`, this test fails nine times, including the reported bug:

```
dark  overlay vs control-hover   dE 0.0030   ← the reported bug
dark  overlay vs line            dE 0.0104   ← dividers invisible in menus
dark  card vs control            dE 0.0153   ← a button on a card has no edge
dark  well vs input              dE 0.0200
light card vs control            dE 0.0000
light card vs overlay            dE 0.0000
light well vs input              dE 0.0090
light chrome vs control-hover    dE 0.0071   ← header hover nearly invisible
dark  muted on overlay           Lc 37.5     (floor 60)
dark  accent-text on overlay     Lc 51.1     (floor 60)
dark  danger on overlay          Lc 36.8     (floor 60)
```

Against the token set in section 2, it passes with no exemptions beyond the four listed.

### The one test that settles it

Change the whole look by editing only `ui/tokens.css`, with zero files in `ui/*.tsx` and zero files in `components/` touched. If that fails, the component that blocked it is reaching outside its tokens, and it is the one that will break the next change too.

### Health metric

`grep -rE '\[(#|[0-9]+px|[0-9]+%)|/(1[0-2]|[1-9])\b' web/src --include='*.tsx' | wc -l`, printed by the test run. Today it is over sixty. It should trend to zero and never rise in a pull request.

---

## 7. Migration

Nine steps. Each one compiles, runs, and is a separate commit.

**Step 0 — `lib/settings.ts`.** Add `updateSettings(current, patch)` and route all four call sites through it (`SettingsSheet.tsx:42`, `App.tsx:143`, `ComposerControls.tsx:42`, `AgentMenu.tsx:61`). No UI change. This fixes a real data-loss bug and unblocks nothing, so do it first and separately.

**Step 1 — token file.** Create `ui/tokens.css` with the ramps, the alphas, the roles and the scales from section 2. In it, keep the five deleted names as temporary aliases:
```css
--c-overlay-hover: var(--state-hover);   /* removed in step 4 */
```
so nothing breaks yet. Import it at the top of `index.css`. The app now looks right — the hover collision is gone, dark muted text is readable, dividers are visible — and no `.tsx` file has changed.

**Step 2 — base rules.** Create `ui/base.css` with section 2.5 and import it. Add `data-surface` to `Surface` and `Bar`, and `data-pressable` to `Button`, `IconButton` and `Toggle`. Delete `focusRing` and `disabled` from `ui/styles.ts` and remove them from every kit component — the base layer now does both. The chrome-coloured focus halo disappears everywhere at once, and the four controls with no focus ring get one.

**Step 3 — scales.** Create `ui/variants.ts` with the height, text and radius maps and the variant tables. Rewrite `Button` and `IconButton` against them. `IconButton size="sm"` becomes 28, matching `Button size="sm"`. Fix the two call sites that relied on the old 24. The composer row now lines up.

**Step 4 — derived states.** Replace every `bg-control-hover`, `bg-overlay-hover`, `bg-control-active`, `bg-overlay-active` and `bg-input-focus` in `ui/` and `components/` with `data-pressable`. Delete the five aliases from step 1. Fourteen call sites; the change is mechanical.

**Step 5 — Radix.** `npm install radix-ui`. Add `ui/Menu.tsx` and `ui/Popover.tsx` with the four required settings and the window-blur close. Port in this order, one commit each:
1. `AgentMenu.tsx` — the smallest, and the one whose hand-rolled Escape handling is already the trickiest.
2. The confirm popover in `ComposerControls.tsx` — gains dismissal for the first time.
3. `HistoryMenu.tsx` — deletes the backdrop that currently blocks the entire header while it is open, and the `top-12` guess at the header height.

Then simplify `App.tsx:106-115`: Escape now only hides the panel or leaves settings, because each floating surface stops its own Escape at the layer.

**Step 6 — missing components.** Add `Dot`, `Eyebrow`, `Hint`, `Label`, `Meter`, `ListRow`, `Pill`, `Bubble`, `Divider`, `Sheet`, `Empty`, `Icon`, `DragRegion`. Each one lands with the call sites that were rebuilding it, in the same commit — a component with no caller is a component nobody checked.

**Step 7 — `DragRegion` and the keyboard.** Replace all eight `startDrag` call sites. Header buttons get real `onClick` handlers. Tab plus Enter works in the header for the first time. Delete the empty `<div aria-hidden>` at `Header.tsx:33` and the duplicated comment above it.

**Step 8 — close the doors.** Drop `className` from every kit prop type and fix what stops compiling. Delete `ui/styles.ts` and `ui/Feedback.tsx`. Delete `StartListening`. Add the ESLint and stylelint rules from section 6 and `web/tokens.test.mjs`, and add `npm test` to the existing workflow.

**Step 9 — audit.** Run the health-metric grep. Anything left is either a token that is missing or a component that is missing. Fix by adding to the kit, never by adding an exception.
