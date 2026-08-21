/**
 * The rules that keep the kit honest, as a test.
 *
 * The spec called for ESLint and stylelint. This does the same three checks by
 * reading the files, and it is the version that actually runs: it adds no
 * dependencies, needs no config, and starts in a few milliseconds, so it goes
 * in `npm run build` instead of in a pull request someone means to open later.
 *
 * Rule 4 — no `className` on a kit component — is not here. It is a type error,
 * which `tsc --noEmit` already catches in the same build.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const files = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return files(path)
    return /\.(tsx|ts|css)$/.test(path) ? [path] : []
  })

const KIT = 'src/ui'
const VIEWS = 'src/components'
const failures = []

const check = (path, line, number, message) =>
  failures.push(`${path}:${number}  ${message}\n    ${line.trim()}`)

for (const path of files('src')) {
  const source = readFileSync(path, 'utf8')
  const isView = path.startsWith(VIEWS)
  // The one file the rule names — not the whole kit directory, which is how
  // every stylesheet in it was escaping the check.
  const isToken = path === join(KIT, 'tokens.css')

  source.split('\n').forEach((line, index) => {
    const number = index + 1
    if (line.trimStart().startsWith('//') || line.trimStart().startsWith('*')) return

    // Rule 1 — no raw values. `-[var(--x)]` is a token reference and fine;
    // `-[13px]`, `-[#2b2b2b]`, `-[85%]` and `oklch(...)` are not.
    if (!isToken && /-\[(#|\d|oklch|rgb|hsl)/.test(line)) {
      check(path, line, number, 'raw value in a class — add a token in ui/tokens.css')
    }
    // `oklch(from …)` is the derived-state mechanism and belongs everywhere.
    // A literal `oklch(62% …)` does not.
    if (!isToken && /\boklch\((?!from\b)|#[0-9a-fA-F]{3,8}\b/.test(line)) {
      check(path, line, number, 'colour literal outside ui/tokens.css')
    }
    // An opacity modifier is a colour nobody named. `bg-accent/12` is invisible
    // to the token test, so it is exactly where a contrast bug hides.
    if (/\b(bg|text|border|ring|fill|divide)-[a-z-]+\/\d/.test(line)) {
      check(path, line, number, 'opacity modifier on a colour — name it in ui/tokens.css')
    }
    // Disabled is a colour now, not a fade. Fading a translucent panel lets the
    // desktop through the control.
    if (/\bopacity-\d/.test(line)) {
      check(path, line, number, 'opacity- utility — disabled and muted are colours')
    }

    if (!isView) return

    // Rule 2 — views may not build controls.
    const element = line.match(/<(button|input|textarea|select|label|hr)\b/)
    if (element) {
      check(path, line, number, `<${element[1]}> in a view — use the kit`)
    }

    // Rule 3 — views may not own floating behaviour.
    if (/\b(window|document)\.addEventListener/.test(line)) {
      check(path, line, number, 'event listener in a view — dismissal belongs to the kit')
    }
    if (/\bz-\d|\bz-\[/.test(line)) {
      check(path, line, number, 'stacking level in a view — only Menu and Popover set one')
    }
    if (/className="[^"]*\b(fixed|absolute)\b/.test(line)) {
      check(path, line, number, 'anchoring in a view — the primitive positions itself')
    }
  })
}

if (failures.length > 0) {
  console.error(`\n${failures.length} rule violation(s):\n`)
  console.error(failures.join('\n'))
  process.exit(1)
}

// The health metric from the spec: raw pixel, hex and percent values, plus
// opacity modifiers, across the whole interface. It should only ever fall.
const raw = files('src').reduce((total, path) => {
  const source = readFileSync(path, 'utf8')
  return total + (source.match(/-\[(#|\d)|\/(1[0-2]|[1-9])\b/g) ?? []).length
}, 0)

console.log(`rules ok — no raw values, no controls in views, no floating in views (raw count ${raw})`)
