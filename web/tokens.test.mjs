/**
 * Arithmetic checks on the token file. No browser, no screenshots.
 *
 * This exists because a hover colour and the menu it sat on were both
 * oklch(31%), so hovering a row did nothing visible. Nobody could see it in
 * the file — two independent numbers that happened to meet. A test can.
 *
 *   node web/tokens.test.mjs
 *
 * Three assertions:
 *   1. Surfaces that can touch are far enough apart, measured in OKLab.
 *   2. Text clears its contrast floor on every surface it can land on, at rest
 *      and hovered, measured with APCA (Accessible Perceptual Contrast
 *      Algorithm).
 *   3. Every colour is inside the sRGB gamut, so nothing clips on screen.
 *
 * Surfaces use lightness distance and text uses APCA on purpose. APCA clips low
 * contrast to zero, so it scores the bug and a healthy step identically. WCAG
 * (Web Content Accessibility Guidelines) 2 ratios are useless here too — every
 * dark surface pair lands between 1.01 and 1.32.
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))
const css = readFileSync(join(here, 'src/ui/tokens.css'), 'utf8')

/** Minimum OKLab distance between two surfaces that can sit on each other. */
const SURFACE_FLOOR = 0.025

/** APCA Lc floors, by how small and how important the text is. */
const TEXT_FLOORS = { ink: 75, muted: 60, 'accent-text': 60, 'danger-text': 60, faint: 28 }

/** Deliberate matches, each with the reason it is allowed. */
const EXEMPT = new Set([
  'light card/overlay',   // both pure white, separated by the strong border
  'light card/control',   // a white button on a white card is the macOS look
  'light overlay/control',
  'light well/input',     // an input never sits on the well
  'light card/input',
  'light chrome/control',
  'light chrome/overlay',
  'light chrome/card',
])

/** Surfaces that host pressable rows, so a hover is derived from them.
 *  Not 'input': base.css re-bases anything pressable inside the input well to
 *  --s-3, because stepping --s-0 darker drove muted text under its floor. */
const HOVERABLE = ['chrome', 'card', 'overlay', 'well']

/** Which surfaces a thing can actually land on. */
const CAN_TOUCH = {
  well: ['card', 'input', 'code'],
  chrome: ['control', 'input'],
  card: ['control', 'code', 'input'],
  overlay: ['control'],
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

function block(name) {
  // The dark block is the only one inside a media query.
  if (name === 'dark') {
    const start = css.indexOf('@media (prefers-color-scheme: dark)')
    return css.slice(start, css.indexOf('\n}\n', css.indexOf(':root', start)))
  }
  return css.slice(0, css.indexOf('@media'))
}

function ramps(appearance) {
  const scoped = block(appearance)
  const base = appearance === 'dark' ? { ...ramps('light') } : {}
  const found = { ...base }

  for (const [, name, l, c, h] of scoped.matchAll(
    /--([a-z0-9-]+):\s*oklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)/g,
  )) {
    found[name] = { l: Number(l) / 100, c: Number(c), h: Number(h) }
  }
  for (const [, name, value] of scoped.matchAll(/--(state-step|alpha-[a-z]+):\s*(-?[\d.]+)/g)) {
    found[name] = Number(value)
  }
  return found
}

/** Roles map to ramp steps. Kept in step with the role block in tokens.css. */
const ROLE_OF = {
  well: 's-1', input: 's-0', code: 's-2', chrome: 's-3',
  control: 's-4', card: 's-5', overlay: 's-6',
  ink: 't-3', muted: 't-2', faint: 't-1',
  line: 'b-1', 'line-strong': 'b-2',
  'accent-text': 'a-text', 'danger-text': 'd-text',
  'accent-soft': 'a-soft', 'danger-soft': 'd-soft',
}

/** The fills a control wears while it is held on, and the text on each. */
const PRESSED = [
  ['accent-soft', 'accent-text'],
  ['danger-soft', 'danger-text'],
]

/** Where a held fill actually appears: the header strip, and the composer's
 *  toolbar. Menus mark their choice with a tick instead. */
const PRESSED_ON = ['chrome', 'input']

/** Higher than the surface floor on purpose. A boundary between two panes only
 *  has to be findable; a control that is switched on has to be noticed without
 *  being looked for. The header's lit button used the control surface, which
 *  measures 0.0253 against the strip behind it — inside the surface floor, and
 *  invisible in use. */
const PRESSED_FLOOR = 0.04

// ---------------------------------------------------------------------------
// Colour maths
// ---------------------------------------------------------------------------

function toLinear(v) { return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4 }
function toSrgb(v) { return v <= 0.0031308 ? v * 12.92 : 1.055 * v ** (1 / 2.4) - 0.055 }

function oklchToRgb({ l, c, h }) {
  const rad = (h * Math.PI) / 180
  const a = c * Math.cos(rad)
  const b = c * Math.sin(rad)

  const l_ = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const m_ = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const s_ = (l - 0.0894841775 * a - 1.2914855480 * b) ** 3

  return {
    r: toSrgb(4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_),
    g: toSrgb(-1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_),
    b: toSrgb(-0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_),
  }
}

/** Euclidean distance in OKLab, which is perceptually even. */
function distance(one, two) {
  const a1 = one.c * Math.cos((one.h * Math.PI) / 180)
  const b1 = one.c * Math.sin((one.h * Math.PI) / 180)
  const a2 = two.c * Math.cos((two.h * Math.PI) / 180)
  const b2 = two.c * Math.sin((two.h * Math.PI) / 180)
  return Math.hypot(one.l - two.l, a1 - a2, b1 - b2)
}

/** APCA Lc, absolute value. */
function apca(text, background) {
  const luminance = (colour) => {
    const { r, g, b } = oklchToRgb(colour)
    const clamp = (v) => Math.min(1, Math.max(0, v))
    return 0.2126729 * toLinear(clamp(r)) ** 1 + 0.7151522 * toLinear(clamp(g)) + 0.0721750 * toLinear(clamp(b))
  }
  let bg = luminance(background) ** 0.56
  let fg = luminance(text) ** 0.57
  const dark = luminance(background) > luminance(text)
  if (!dark) {
    bg = luminance(background) ** 0.65
    fg = luminance(text) ** 0.62
  }
  return Math.abs((dark ? bg - fg : bg - fg) * 1.14) * 100
}

/** A hover is the surface, stepped. Exactly what the stylesheet computes. */
function stepped(surface, step) {
  return { ...surface, l: Math.min(1, Math.max(0, surface.l + step)) }
}

const clamp = (v) => Math.min(1, Math.max(0, v))

/** Linear sRGB back to OKLCH, so a blended colour can be measured like any other. */
function rgbToOklch([r, g, b]) {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  const A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

  return { l: L, c: Math.hypot(A, B), h: (Math.atan2(B, A) * 180) / Math.PI }
}

/** Alpha-composite one colour over another, the way the screen does — in
 *  linear light, not by averaging the numbers in the file. */
function over(top, bottom, alpha) {
  const linear = (colour) => {
    const { r, g, b } = oklchToRgb(colour)
    return [toLinear(clamp(r)), toLinear(clamp(g)), toLinear(clamp(b))]
  }
  const t = linear(top)
  const u = linear(bottom)
  return rgbToOklch(t.map((v, i) => v * alpha + u[i] * (1 - alpha)))
}

// ---------------------------------------------------------------------------
// The checks
// ---------------------------------------------------------------------------

const failures = []

for (const appearance of ['light', 'dark']) {
  const r = ramps(appearance)
  const colour = (role) => r[ROLE_OF[role]]
  const step = r['state-step']

  // 1. Surfaces that can touch, including the derived states.
  for (const [under, overs] of Object.entries(CAN_TOUCH)) {
    for (const over of overs) {
      const pair = `${appearance} ${under}/${over}`
      if (EXEMPT.has(pair)) continue
      const d = distance(colour(under), colour(over))
      if (d < SURFACE_FLOOR) failures.push(`${pair}  dE ${d.toFixed(4)}  (floor ${SURFACE_FLOOR})`)
    }

    // The hover derived from this surface must differ from the surface itself.
    if (HOVERABLE.includes(under)) {
      const d = distance(colour(under), stepped(colour(under), step))
      if (d < SURFACE_FLOOR) {
        failures.push(`${appearance} ${under}/hover  dE ${d.toFixed(4)}  (floor ${SURFACE_FLOOR})`)
      }
    }
  }

  // A border has to be visible on the surfaces it outlines.
  for (const surface of ['chrome', 'card', 'overlay']) {
    const d = distance(colour(surface), colour('line'))
    if (d < SURFACE_FLOOR) {
      failures.push(`${appearance} ${surface}/line  dE ${d.toFixed(4)}  (floor ${SURFACE_FLOOR})`)
    }
  }

  // A divider is ink at alpha, so it has to be measured composited — and on
  // EVERY surface, including the input well. Checking only chrome, card and
  // overlay is how the composer shipped with a divider nobody could see.
  for (const surface of ['well', 'chrome', 'card', 'overlay', 'input']) {
    const line = over(colour('muted'), colour(surface), r['alpha-divider'])
    const d = distance(colour(surface), line)
    if (d < SURFACE_FLOOR) {
      failures.push(`${appearance} ${surface}/divider  dE ${d.toFixed(4)}  (floor ${SURFACE_FLOOR})`)
    }
  }

  // A control that is held on has to be obvious against whatever it sits on.
  // This is the check that was missing. In the light ramp every surface above
  // the chrome is pure white, so a held control that raised itself a step had
  // nothing to raise itself against.
  for (const [fill, text] of PRESSED) {
    for (const surface of PRESSED_ON) {
      const d = distance(colour(surface), colour(fill))
      if (d < PRESSED_FLOOR) {
        failures.push(`${appearance} ${fill} held on ${surface}  dE ${d.toFixed(4)}  (floor ${PRESSED_FLOOR})`)
      }
      const lc = apca(colour(text), colour(fill))
      if (lc < TEXT_FLOORS[text]) {
        failures.push(`${appearance} ${text} on ${fill}  Lc ${lc.toFixed(1)}  (floor ${TEXT_FLOORS[text]})`)
      }
    }
  }

  // 2. Text on every surface it can land on, at rest and hovered.
  for (const [role, floor] of Object.entries(TEXT_FLOORS)) {
    for (const surface of ['well', 'chrome', 'card', 'overlay', 'input']) {
      const backgrounds = [['', colour(surface)]]
      if (HOVERABLE.includes(surface)) {
        backgrounds.push([' hovered', stepped(colour(surface), step)])
      }

      for (const [state, background] of backgrounds) {
        const lc = apca(colour(role), background)
        if (lc < floor) {
          failures.push(`${appearance} ${role} on ${surface}${state}  Lc ${lc.toFixed(1)}  (floor ${floor})`)
        }
      }
    }
  }

  // 3. Nothing outside sRGB, which looks fine in the file and clips on screen.
  for (const [name, value] of Object.entries(r)) {
    if (typeof value !== 'object') continue
    const { r: red, g, b } = oklchToRgb(value)
    for (const [channel, v] of [['r', red], ['g', g], ['b', b]]) {
      if (v < -0.001 || v > 1.001) {
        failures.push(`${appearance} --${name}  outside sRGB (${channel} ${v.toFixed(3)})`)
      }
    }
  }
}

if (failures.length) {
  console.error(`\n${failures.length} token problem${failures.length === 1 ? '' : 's'}:\n`)
  for (const failure of failures) console.error(`  ${failure}`)
  console.error('')
  process.exit(1)
}

console.log('tokens ok — surfaces separable, text readable, all in gamut')
