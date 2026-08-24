import { cx } from './variants'

/** A slow pulse, not a spinner — it sits beside text, not in a dialog. */
export function Pulse() {
  return <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-accent-text" />
}

/** A red dot that breathes. Recording, capturing — anything live. */
export function LiveDot() {
  return <span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-danger" />
}

export function Hint({ children }: { children: React.ReactNode }) {
  return <p className="mt-0.5 text-xs leading-relaxed text-muted">{children}</p>
}

export function Notice({
  tone = 'muted',
  children,
}: {
  tone?: 'muted' | 'danger'
  children: React.ReactNode
}) {
  return (
    <div
      data-surface={tone === 'danger' ? undefined : 'card'}
      className={cx(
        'selectable break-words rounded-md border px-3 py-2 text-sm leading-relaxed',
        tone === 'danger'
          ? 'border-danger-line bg-danger-soft text-danger-text'
          : 'border-line text-muted',
      )}
    >
      {children}
    </div>
  )
}

/**
 * A card marked as coming from Companion rather than from your question.
 *
 * The accent edge is the whole point: something that arrived unprompted has to
 * look different, or it reads as a reply to a question nobody asked.
 */
export function Callout({
  title,
  action,
  children,
}: {
  title: string
  action?: React.ReactNode
  children: React.ReactNode
}) {
  return (
    <div data-surface="card" className="rounded-lg border-l-2 border-accent px-3 py-2.5">
      <div className="mb-1 flex items-center gap-2">
        <span className="text-2xs font-semibold uppercase tracking-caps text-accent-text">
          {title}
        </span>
        {action && <span className="ml-auto">{action}</span>}
      </div>
      {children}
    </div>
  )
}

/** A caption above a group of settings. */
export function GroupTitle({ children }: { children: React.ReactNode }) {
  return <h3 className="text-xs font-semibold uppercase tracking-caps text-muted">{children}</h3>
}

/**
 * A level meter that reads like a voice rather than a number.
 *
 * Root mean square of speech sits low in a 0-1 range, so a linear bar barely
 * moves. The cube root opens up the quiet end, which is where conversation is.
 */
export function Meter({ label, level }: { label: string; level: number }) {
  const filled = Math.min(1, Math.cbrt(Math.max(0, level)) * 1.35)

  return (
    <div className="min-w-0 flex-1">
      <span className="text-2xs font-medium uppercase tracking-caps text-muted">{label}</span>
      <div data-surface="input" className="mt-1 h-1 overflow-hidden rounded-full">
        <div
          className="h-full rounded-full bg-accent transition-[width] duration-75"
          style={{ width: `${filled * 100}%` }}
        />
      </div>
    </div>
  )
}
