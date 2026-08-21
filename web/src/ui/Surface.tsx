import { cx } from './variants'

type Level = 'well' | 'chrome' | 'card' | 'overlay' | 'input' | 'code'

const radii = { sm: 'rounded-sm', md: 'rounded-md', lg: 'rounded-lg' } as const
const paddings = ['p-0', 'p-1', 'p-2', 'p-3'] as const

/**
 * A surface at a named level.
 *
 * Sets `data-surface`, which does two things: paints the background from the
 * matching token, and declares `--surface` so everything inside derives its
 * own hover and active from it. That is the mechanism that makes a hover
 * matching its own background impossible.
 */
export function Surface({
  level = 'card',
  radius = 'lg',
  padding = 0,
  children,
  ...props
}: Omit<React.HTMLAttributes<HTMLDivElement>, 'className'> & {
  level?: Level
  radius?: keyof typeof radii
  padding?: 0 | 1 | 2 | 3
  children: React.ReactNode
}) {
  return (
    <div
      data-surface={level}
      {...props}
      className={cx(
        radii[radius],
        paddings[padding],
        level === 'overlay' && 'border border-line-strong',
      )}
    >
      {children}
    </div>
  )
}

/**
 * A chrome strip — the header or the composer.
 *
 * The hairline goes on the side facing the conversation, so the well reads as
 * inset between them rather than as one flat sheet.
 */
export function Bar({
  edge,
  children,
  ...props
}: Omit<React.HTMLAttributes<HTMLDivElement>, 'className'> & {
  edge: 'top' | 'bottom'
  children: React.ReactNode
}) {
  return (
    <div
      data-surface="chrome"
      {...props}
      className={cx('shrink-0', edge === 'bottom' ? 'border-b border-line' : 'border-t border-line')}
    >
      {children}
    </div>
  )
}

/** A scrolling body with an action floating over its end. */
export function Sheet({ children, action }: { children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div data-surface="well" className="relative flex min-h-0 flex-1 flex-col">
      <div className={cx('min-h-0 flex-1 space-y-6 overflow-y-auto p-3', action ? 'pb-16' : null)}>
        {children}
      </div>
      {action && (
        <div className="pointer-events-none absolute inset-x-0 bottom-0 p-2">
          <div className="pointer-events-auto">{action}</div>
        </div>
      )}
    </div>
  )
}

export function Divider() {
  return <div className="h-px" style={{ background: 'var(--c-line)' }} />
}
