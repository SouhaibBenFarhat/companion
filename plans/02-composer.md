# Composer settings row — Companion

Specification for `web/src/components/ComposerControls.tsx` and its neighbours. Everything below is decided. No open choices.

Files touched:

- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/components/ComposerControls.tsx` — rewritten
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/components/AgentMenu.tsx` — new
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/components/Composer.tsx` — the control row moves inside the input well
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/components/AwarenessBar.tsx` — gains the speak-up switch
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/ui/Chip.tsx` — deleted
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/ui/styles.ts` — one addition
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/ui/Toggle.tsx` — one line
- `/Users/souhaib.farhat/Desktop/Souhaib-DEV/companion/web/src/index.css` — one keyframe

---

## 1. Why the five pills read as cheap

Each point is a real line in the current file, matched to the research that says not to do it.

1. **Five identical shapes say nothing was decided.** Every shipped composer puts *one* setting at rest and hides the rest. Claude shows one text label. ChatGPT shows a plus and a model name. A row of five equal pills tells the reader that the app has no opinion about which of them matters. It is the visual signature of a settings screen that leaked into a toolbar.

2. **The shape does not match the value.** All five are `<Chip>`. But the five values are five different kinds: a command that opens a folder picker (repo), a one-of-N choice (agent), a dangerous two-state (permission), a session state (listening), and a two-state that only means something inside another one (speak up). Three separate sources in the research say the same thing — pick the control from the shape of the value.

3. **Two commands are dressed as toggles.** The repo chip opens a native picker. It holds no state, yet it has an `active` prop and a pressed look available to it. Giving a command an on-state teaches a wrong model.

4. **An error and an armed setting are drawn the same.** In the current code the agent chip uses `active={!agent.found}` with `tone="danger"`, and the permission chip uses `active={!readOnly}` with `tone="danger"`. Both come out as a red-tinted pill with red text. "Something is broken" and "you deliberately gave the agent write access" must never share a drawing.

5. **The row wraps.** `flex flex-wrap` means five chips can reflow to two lines. That changes the composer height and pushes the text area down while someone is typing. A toolbar must never wrap.

6. **Three heights and four corner radii in one 460 point panel.** Chips are `h-6 rounded-full` (24px, pill). `IconButton` is `h-7 rounded-md` (28px, 6px). `Button` is `h-8 rounded-lg` (32px, 8px). The input well is `rounded-xl` (12px). Mixed heights and radii is the fastest way to make a toolbar look assembled from parts.

7. **A second icon size and stroke.** The file declares `const ICON = 12` and `const STROKE = 2` while the kit ships `iconSize = 14` and `iconStroke = 1.75`. Two stroke weights in one panel is visible instantly.

8. **Five painted boxes stacked on a sixth.** Every chip carries a border in every state. The rest of the kit is borderless until you touch it. Five outlined pills sitting directly above the outlined input well is five boxes too many.

9. **Everything can change width.** All five carry `max-w-[9rem] truncate`. Any of the five can resize on a state change and slide the whole row. Exactly one element in a row should be allowed to shrink.

10. **They sit above the box.** The chips render above the input well. The research is unanimous across six products: settings go *below* the text, *inside* the same rounded card. Above the box is for things that disappear.

11. **Blind cycling.** Clicking the agent chip flips Claude Code to Codex with no confirmation and no view of the alternative. That is not how you choose one of N when one of them can be missing.

12. **Five tab stops before the send button.** The composer should be three stops, not eight.

13. **No primary action.** Send lives inside the well, below the pills. The eye meets five equal pills first and the actual button last.

---

## 2. Layout

The control row moves **inside the input well**, on the bottom edge, sharing one line with Stop and Send. The repo leaves the composer. Speak up leaves the composer. Three controls on the left, one or two on the right.

```
PANEL 460pt — at rest, not listening
────────────────────────────────────────────────────────────────────────

 ┌───────────────────────────────────────────────────────────────────┐
 │  … message list …                                                 │
 ├───────────────────────────────────────────────────────────────────┤ ← Bar edge="top"
 │                                                                   │   bg-chrome, p-2.5 (10px)
 │  ┌─────────────────────────────────────────────────────────────┐  │
 │  │ Ask about this repo…                                        │  │ ← the well
 │  │                                                             │  │   rounded-xl
 │  │                                                             │  │   border-line-strong
 │  │                                                             │  │   bg-input, px-3
 │  │                                                             │  │   3 rows min (58px)
 │  │  ─── 6px (pt-1.5) ──────────────────────────────────────────│  │
 │  │                                                             │  │
 │  │   Claude Code (v)   (L) Read only   (M)              ( ^ )  │  │ ← the row, 28px tall
 │  │   └──── 101 ────┘   └──── 90 ────┘  └28┘             └28┘   │  │
 │  │        agent          permission     mic              send  │  │
 │  │                                                             │  │
 │  └─────────────────────────────────────────────────────────────┘  │
 │                                                                   │
 │   Enter to send · Shift+Enter for a new line · Esc to hide        │ ← Hint, also a drag grip
 └───────────────────────────────────────────────────────────────────┘

   (v) = chevron   (L) = Lock   (M) = Mic   ( ^ ) = ArrowUp, accent fill

   No box is painted at rest. The widths above are hit areas, not borders.
   Left group is flush with the text caret. Send is flush right (ml-auto).
   Total left group = 227px of 416px available. The gap is the design.
```

```
PANEL 460pt — listening, speak up on, edits allowed
────────────────────────────────────────────────────────────────────────

 ├───────────────────────────────────────────────────────────────────┤
 │  (o) Listening · Google Meet        Speak up (=O)          Stop   │ ← AwarenessBar
 │   YOU  ▁▃▂▁▁            THE CALL  ▁▁▅▃▂                           │   only exists while listening
 │   them: so if we change the retry window…                         │
 ├───────────────────────────────────────────────────────────────────┤
 │  ┌─────────────────────────────────────────────────────────────┐  │
 │  │ Ask about this repo…                                        │  │
 │  │                                                             │  │
 │  │   Claude Code (v)  ┏(P) Can edit┓  (M)·             ( ^ )   │  │
 │  │                    ┗━ solid ━━━━┛   ^                       │  │
 │  │                     danger/35       accent/12 + dot badge   │  │
 │  └─────────────────────────────────────────────────────────────┘  │
```

```
PANEL 460pt — agent menu open
────────────────────────────────────────────────────────────────────────

 │  ┌─────────────────────────────────────────────────────────────┐  │
 │  │┌───────────────────────────────┐                            │  │
 │  ││ (/) Claude Code               │ ← Surface level="overlay"  │  │
 │  ││     Ready · 1.2.3             │   rounded-xl, p-1          │  │
 │  ││                               │   min-w 200, max-w well-8  │  │
 │  ││     Codex                     │   opens UPWARD, mb-1.5     │  │
 │  ││     Not found — set the path  │   left edge = trigger left │  │
 │  ││ ───────────────────────────── │   divider: h-px bg-line    │  │
 │  ││ (F) Change repo…              │                            │  │
 │  ││ (S) Agent settings…           │                            │  │
 │  │└───────────────────────────────┘                            │  │
 │  │ Ask about this repo…                                        │  │
 │  │                                                             │  │
 │  │  ▓Claude Code (v)▓  (L) Read only   (M)              ( ^ )  │  │
 │  │  ^ bg-control-active while open                             │  │
 │  └─────────────────────────────────────────────────────────────┘  │

   (/) = Check, in a fixed 16px column reserved on EVERY row.
```

```
PANEL 320pt — one breakpoint fires
────────────────────────────────────────────────────────────────────────

 ┌────────────────────────────────────────┐
 │  ┌──────────────────────────────────┐  │
 │  │ Ask about this repo…             │  │
 │  │                                  │  │
 │  │                                  │  │
 │  │  Claude Code (v) (L) (M)   ( ^ ) │  │
 │  │  └── 101 ──────┘ └28┘└28┘  └28┘  │  │
 │  └──────────────────────────────────┘  │
 │   Enter to send · Esc to hide          │
 └────────────────────────────────────────┘

 What changed, and only this:
   · permission drops its label, keeps the lock glyph — 90px becomes 28px
   · the Hint line drops the Shift+Enter clause
 What never changes:
   · nothing wraps, ever
   · the row height stays 28px, so the panel height never moves
   · the agent label is the ONLY element allowed to shrink (truncate)
   · when permission is "Can edit" the label stays, at every width
```

**The one breakpoint.** Put `@container` on the input well. The well's content box is the panel width minus 44px (10px bar padding each side, 12px well padding each side). Show the permission label and the long Hint at `@[320px]` and up — that is a panel of 364 points and wider. Below that, both shorten. There are no other breakpoints in the composer.

**Width budget at the smallest supported size.** Panel 320 → well content 276px. Fixed cost: permission 28 + mic 28 + send 28 + three 4px gaps + 8px before send = 104px. Agent trigger fixed parts (16px padding, 4px gap, 13px chevron) = 33px. The label gets 139px; "Claude Code" needs about 68px. Set the app's minimum window width to 320 points.

---

## 3. The five settings

### 3.1 Repo — **not in the composer**

**Control kind:** none in the composer. It stays as the header title button, which already shows the folder name and already opens the native picker on click. It gains a second route: a `Change repo…` row at the foot of the agent menu.

**Why.** Two reasons from the research, and they agree.

- A repo is a property of the whole conversation, not of one message. Claude keeps `Add to project` off the composer for exactly this reason: "a project is a property of the whole conversation, so it belongs to the page frame rather than the message toolbar." Companion's own history menu proves the point — conversations are already listed per repo ("No conversations about this repo yet").
- It is already on screen, about 40 points above, in `Header.tsx`. Printing the same folder name twice in a 460 point panel is the cheapest thing the row does.

It stays reachable during a call: header click, or the menu row that is one click from the composer.

### 3.2 Agent — **dropdown, and the only control with a text label at rest**

**Control kind:** a pop-up button. Plain text showing the current value, a chevron, no icon, no border, no fill. It opens a menu (see section 4).

**Why.** Three sources converge:

- "One value out of a set that can grow past five, and the current value must be readable without opening anything" is the definition of a pop-up button in the Apple HIG (Human Interface Guidelines).
- "Put exactly one setting at rest, and make it the one with the highest cost." The agent is which brain answers, and it is the one that can be missing entirely. It earns the only label.
- "Never show a name without a meaning." `Claude Code` and `Codex` mean nothing without a second line, so the menu rows carry a state line each.
- No leading icon, because a terminal glyph cannot tell Claude Code from Codex. ChatGPT and Claude both ship the model picker as bare text plus chevron. The icon slot is reserved for the error dot.

Cycling on click is removed. A one-of-N with a possible error state needs a menu you can read.

### 3.3 Permission — **pressed icon button with a label, and a confirm on the way up**

**Control kind:** a two-state button using `aria-pressed`, not a switch. Icon plus label at ≥364 points, icon only below. Turning it **on** opens a confirm popover. Turning it **off** is one click, no confirm.

**Why.**

- "In a compact row a switch is almost always the wrong shape even when the value is a plain boolean. It is two to three times the width of the alternatives and carries settings-screen weight. Use a pressed icon button in the row, and keep real switches for a settings list one layer deeper."
- The research also says to keep dangerous permissions out of the composer entirely — but that assumes the user never needs them mid-call, and here they do. The split that satisfies both: the **readout** is in the composer at all times, the **arming** costs two clicks. You can always see the state; you cannot reach it by accident.
- Zed is named in the research as the one product that puts permission on the composer as its own named control, and as the model to copy if you want the risk visible. Companion wants it visible: the agent can write to the repo being shown on a shared screen.
- It is the only control that keeps its label at every panel width. A dangerous state must never be carried by a glyph alone.

Glyphs: `ReadOnlyIcon` (Lock) when off, `EditsIcon` (PencilLine) when on.

### 3.4 Listening — **plain icon toggle, and never `disabled`**

**Control kind:** one square icon button. Three drawings: off, on, unavailable. `ListenIcon` (Mic) when off or on, `MutedIcon` (MicOff) when unavailable.

**Why.**

- It is a session state with no configuration, so it gets a bare icon button and no menu. ChatGPT's dictation button is the same: "One instant action with no configuration, so no menu."
- The live readout is not the button's job. `AwarenessBar` already shows the pulse, the call app, both meters, the transcript and a Stop button, and it only exists while listening. "Read-only status gets no button chrome." The button is the switch; the bar is the readout.
- **Unavailable is not off, and not disabled.** The kit's `disabled` is `opacity-45` plus `pointer-events-none`, which is a dead end with no explanation. The research is explicit: "Dim it when the user could unlock it; remove it when they never can" — and the user *can* unlock it by granting the macOS permission. So the unavailable button stays clickable and routes to the fix: clicking opens the Settings sheet at the Permissions group. The tooltip carries `permissions.summary`, which already says what is missing.

### 3.5 Speak up unprompted — **not in the composer; a switch in the AwarenessBar**

**Control kind:** a real `Toggle` switch, rendered in the `AwarenessBar` header row, left of Stop. Also present in Settings under "During a call".

**Why.**

- "Show contextual controls only in context. A control that is dead 95% of the time should not be on the bar 100% of the time." Speak up does nothing unless Companion is listening. The AwarenessBar exists only while Companion is listening. The setting and its surface have the same lifetime.
- "Secondary settings nest inside the relevant menu rather than earning their own chip." Here the relevant surface is the bar, not a menu — and a bar has vertical room, so it can afford the switch shape the composer row cannot.
- A switch is right *here* and wrong in the row, for the same reason: "A switch reads as 'this is running'." In the bar that is exactly what it means.

**But it must still be visible at rest.** The research names this as the trap Claude's own composer falls into: "Anything that changes the answer and cannot be seen at rest is a trap." So when listening is on **and** speak up is on, the mic button in the composer carries a 6px dot badge. That is the research's own device — "a small dot badge on the icon when any option is off its default" — and it costs zero width. The dot appears for that combination only, because that is the only combination that changes behaviour.

---

## 4. The agent menu

One menu in the composer. Not two. "One entry point beats two."

**Anchoring.** Wrap the trigger in a `relative` element. The menu is `absolute bottom-full left-0 mb-1.5 z-30`. It opens **upward**, because the composer is at the bottom of the panel. It is left-aligned to the trigger's left edge, and the trigger is the leftmost control, so it can never leave the panel. It is a floating layer and may be wider than its trigger.

**Surface.** `<Surface level="overlay">` gives `rounded-xl bg-overlay border border-line-strong`. Add `p-1 min-w-[200px] max-w-[calc(100%-8px)] max-h-[50vh] overflow-y-auto`.

**Rows.** `flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left transition-colors`, hover `bg-control-hover`. About 40px tall because each carries two lines.

| Row | Line 1 | Line 2 |
|---|---|---|
| Claude Code | `text-[12px] font-medium text-ink` | `Ready · {agent.version}` in `text-[11px] text-muted` |
| Codex | same | `Not found — set the path in Settings` in `text-[11px] text-danger` |
| `Change repo…` | `FolderIcon` 14/1.75 + label | — |
| `Agent settings…` | `SettingsIcon` 14/1.75 + label | — |

A not-found agent row stays selectable. The user may want to pick it and then fix the path.

**Grouping.** One divider between the two agents and the two footer rows: `my-1 h-px bg-line`. No headings — four rows do not need them. The footer rows are the management route, which the research insists must live in the menu: "If the only way to add a thing is Settings, people give up at the moment they wanted it."

**How the current choice is shown.** A fixed 16px leading column, reserved on **every** row including the footer rows, so labels never shift sideways. The chosen agent row holds `CheckIcon` at size 13, stroke 2, `text-accent-text`. Never a filled radio dot — a check is the native mark in a macOS menu. Never a highlighted row — highlight means hover and keyboard focus, and it vanishes the moment the pointer moves. The trigger label mirrors the chosen value, so the state is readable with the menu closed.

**No submenus.** "Do not nest submenus in a narrow panel." Depth stops at one level.

**Dismissal.** Escape, outside click, or picking any row. Picking an agent row closes the menu (single choice, radio semantics). The footer rows close it too. Escape closes **one layer only**: the menu container handles the key itself and calls `stopPropagation()`, so the window-level handler in `App.tsx` never sees it and the panel does not hide.

**Keyboard.**

- Trigger carries `aria-haspopup="menu"` and `aria-expanded`. Its accessible name is `Agent: Claude Code` — setting plus value, not value alone.
- Enter, Space, ArrowDown and ArrowUp all open it. ArrowDown lands on the first row; ArrowUp lands on the last.
- ArrowUp/ArrowDown move, Home/End jump, first-letter type-ahead selects, Enter or Space activates.
- Enter while the menu is open must not send the message. Focus is inside the menu, so the textarea's key handler never fires — but assert it in a test.
- Focus return: after a choice, focus goes to the **textarea**, so typing continues. After Escape or an outside click with no choice, focus goes back to the **trigger**.
- While the menu is open the well keeps its focused look (`border-accent bg-input-focus`). Without this the caret disappears and the composer looks switched off. This is a named bug in the research.

**Modality.** Non-modal. No scroll lock, nothing hidden from screen readers. This is a small panel sitting beside live content.

**Motion.** 120ms, fade plus a 3px rise. No scale, no bounce. Add to `index.css`:

```css
@keyframes rise {
  from { opacity: 0; transform: translateY(3px); }
  to   { opacity: 1; transform: none; }
}
```

Trigger stays in the pressed look (`bg-control-active text-ink`) for as long as the menu is open.

### The permission confirm

Not a menu — a confirm, and the only other overlay in the composer. It appears on one transition: read only → can edit.

`absolute inset-x-0 bottom-full mb-1.5 z-30`, so it takes the full width of the well and fits at 320 points without any collision maths. `<Surface level="overlay" className="p-3">` containing:

- One line, `text-[12px] text-ink`: `The agent will be able to change files in this repo.`
- One `<Hint>`: the repo name.
- A right-aligned pair: `<Button variant="ghost" size="sm">Cancel</Button>` then `<Button variant="danger" size="sm">Allow edits</Button>`.

Escape and outside click both cancel. Turning edits **off** never opens this.

---

## 5. Visual specification

### One height, one radius, one icon size

| Property | Value | Applies to |
|---|---|---|
| Control height | **28px** (`h-7`) | every control in the row, including Send |
| Corner radius | **8px** (`rounded-lg`) | every control in the row |
| Icon size / stroke | **14 / 1.75** (`iconSize`, `iconStroke`) | every glyph in the row |
| Chevron size / stroke | **13 / 1.75** | agent trigger only, matching `Select` |
| Gap between controls | **4px** (`gap-1`) | the row |
| Gap icon → label | **6px** (`gap-1.5`) | inside a control |
| Gap text → row | **6px** (`pt-1.5`) | above the row, inside the well |
| Send separated by | `ml-auto` | the Stop/Send group |

`IconButton` ships `rounded-md`. In this row pass `className="rounded-lg"` so the radius is uniform. Delete the `ICON = 12` / `STROKE = 2` constants — that second icon size is one of the reasons the old row looked assembled from parts.

### Shared base class

Add to `ui/styles.ts`:

```ts
/** Same as focusRing, but the offset matches the input well the row sits in. */
export const focusRingOnInput =
  'outline-none focus-visible:ring-2 focus-visible:ring-accent/55 focus-visible:ring-offset-1 focus-visible:ring-offset-input'
```

The kit's `focusRing` offsets against `chrome`. The row sits on `input`, which is a different colour in both themes.

Row control base — every control in the row starts here:

```
inline-flex h-7 shrink-0 items-center gap-1.5 rounded-lg
border border-transparent px-2
text-[12px] font-medium transition-colors
+ focusRingOnInput
```

The **transparent border at rest is required**. Two states paint it. If it were absent at rest, painting it would resize the control and slide its neighbours.

Icon-only variant: `w-7 justify-center px-0`.

### State to token

| State | Background | Text and icon | Border | Extra |
|---|---|---|---|---|
| **Default** (safe, off) | none | `text-muted` | transparent | hover `bg-control-hover` + `text-ink`, press `bg-control-active` |
| **Active** (benign on) | `bg-accent/12` | `text-accent-text` | transparent | hover `bg-accent/18` |
| **Dangerous** (armed) | `bg-danger-soft` | `text-danger` | `border-danger/35`, **solid** | label always shown; press `active:brightness-95` |
| **Unavailable** | none | `text-muted` | `border-dashed border-line-strong` | still clickable; routes to Settings |
| **Error** (agent missing) | none | `text-danger` | transparent | 5px `bg-danger` dot in the icon slot |
| **Open** (menu trigger) | `bg-control-active` | `text-ink` | transparent | held while the menu is up |

### Per control

**Agent trigger**

```
{base} text-[12px]
rest        text-muted hover:bg-control-hover hover:text-ink active:bg-control-active
open        bg-control-active text-ink
not found   text-danger hover:text-danger hover:bg-control-hover
```

No leading icon. When `!agent.found`, a `h-1.5 w-1.5 rounded-full bg-danger` dot takes the icon slot. Label is `min-w-0 truncate` — the only shrinkable element in the row. Chevron is `shrink-0`. Accessible name `Agent: {agent.title}`.

**Permission button**

```
{base}
read only   text-muted hover:bg-control-hover hover:text-ink active:bg-control-active
can edit    border-danger/35 bg-danger-soft text-danger active:brightness-95
```

`aria-pressed={!readOnly}`. Label `Read only` / `Can edit`, wrapped in `<span className="hidden @[320px]:inline">` — except that when `!readOnly` the span is always `inline`. Existing tooltip strings are kept.

**Mic button**

```
{base} w-7 justify-center px-0 relative
off           text-muted hover:bg-control-hover hover:text-ink
on            bg-accent/12 text-accent-text hover:bg-accent/18
unavailable   border-dashed border-line-strong text-muted hover:bg-control-hover
```

`aria-pressed={listening.active}`. Glyph is `ListenIcon` when available, `MutedIcon` when not. Never pass `disabled`. Speak-up dot badge, rendered only when `listening.active && settings.suggestionsEnabled`:

```html
<span class="absolute -right-0.5 -top-0.5 h-1.5 w-1.5 rounded-full bg-accent-text ring-2 ring-input" />
```

**Send** — unchanged apart from the radius. It is the only **solid** fill in the row (`bg-accent text-accent-fg`). The danger and active states are tints, not fills. If any other control gets a solid fill, the row reads as an error state and Send stops standing out.

**Stop** — `<Button variant="ghost" size="sm">` is already `h-7 rounded-lg text-[12px]`. Place it with `ml-auto`, and Send after it.

### AwarenessBar addition

In the header row, between the call-app name and Stop:

```html
<div class="ml-auto flex items-center gap-3">
  <Toggle label="Speak up" checked={settings.suggestionsEnabled} onChange={…} />
  <Button variant="ghost" size="sm">Stop</Button>
</div>
```

One line in `ui/Toggle.tsx`: the switch has `mt-0.5` baked in for the two-line case. Make it conditional — `hint ? 'mt-0.5' : ''` — so it centres when there is no hint.

### Accessibility and tab order

The composer is **three tab stops**: textarea → toolbar → Send.

The row is `role="toolbar" aria-label="Message settings"` with a roving tabindex, per the W3C ARIA APG (World Wide Web Consortium, Accessible Rich Internet Applications Authoring Practices Guide) toolbar pattern. Hold the focused index in state; each control gets `tabIndex={i === focused ? 0 : -1}`; ArrowLeft and ArrowRight move it and call `.focus()`; Home and End jump to the ends. Without this, there are five presses between typing and sending.

Every icon-only button keeps a real `aria-label`. A `title` tooltip is not an accessible name.

### Optional keyboard shortcuts

Three, and note the asymmetry on the third — it can only make things safer.

| Keys | Action |
|---|---|
| `Cmd+J` | open the agent menu |
| `Cmd+L` | toggle listening |
| `Cmd+Shift+E` | force permission back to read only, always; never turns edits on |

---

## 6. Keeping the states apart

Four states, four different mechanisms. None of them relies on hue alone.

- **Fill** separates on from off. Off has no background at all.
- **Hue** separates benign-on (accent) from dangerous-on (danger).
- **Border style** separates unavailable from everything else. It is the only dashed thing in the panel.
- **Text-only colour** separates error from armed-danger. An error colours the text and adds a dot. An armed dangerous setting colours the text *and* fills *and* draws a solid border *and* keeps its word.

Backup signals, so colour is never the only carrier:

| State | Second signal | Third signal |
|---|---|---|
| Dangerous | solid border | label survives every width |
| Unavailable | dashed border | different glyph (`MicOff`) |
| Error | 5px dot in the icon slot | textarea placeholder says which agent is missing |
| Active | tinted fill | the AwarenessBar is on screen |

Two hard rules:

1. **Unavailable is never `disabled`.** It stays clickable and it goes somewhere useful. A greyed control with no path forward is a dead end.
2. **Dangerous is never icon-only.** Every other label may drop at 320 points. This one does not.

---

## 7. What must not be in the composer

| Kept out | Where it goes | Why |
|---|---|---|
| `agentPath` — path to the binary | Settings → Agent | A text field with a filesystem path. Typed once at install. A wrong value breaks everything, so it must not be a click away from a live call. |
| `systemPrompt` — extra instructions | Settings → Answers | A seven-row textarea. It is per-account, not per-message. |
| Microphone / system audio / accessibility grants | Settings → Permissions | Three rows with Grant buttons and a restart note. An install chore. The composer shows only the *consequence* — a dashed mic — and routes here. |
| `persistTranscript` | Settings | A privacy default, set once and never mid-call. |
| The repo picker as a permanent control | Header, plus one menu row | A property of the conversation, not the message. Already on screen 40 points above. |
| History, New conversation, Hide, Settings | Header | Not per-message actions. They would compete for the same pixels. |
| Speak up while not listening | AwarenessBar | It does nothing then. A control that is dead most of the time should not be on the row all of the time. |
| Model or effort pickers | nowhere — do not invent them | Companion does not choose a model. The agent CLI (command line interface) does. |
| Token counts or cost | nowhere yet | If they ever arrive: dim inline text beside the Hint line, no button chrome. Read-only numbers do not deserve a control slot. |

The general split, which is the rule to apply to anything new: **anything that only affects this one send is a control in the row; anything sticky goes one level deeper.** That split is what keeps the row down to three controls.

---

## 8. Deleting the Chip

Delete `web/src/ui/Chip.tsx` and its line in `web/src/ui/index.ts`. A component the spec forbids is how the pill row comes back.

The chip shape is not wrong in general — it is wrong for settings. The research reserves it for one job: **per-message content and armed modes**, drawn as a wrapping row *above* the textarea, inside the well, with a dismiss control on each. Companion has none of those today. When one ships — an attached file, a pinned range of the transcript — that is when a chip returns, in that position, and the settings row is not where it goes.
