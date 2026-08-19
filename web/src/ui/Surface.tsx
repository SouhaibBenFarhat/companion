import { cx } from './styles'

type Level = 'well' | 'chrome' | 'card' | 'overlay'

const levels: Record<Level, string> = {
  well: 'bg-well',
  chrome: 'bg-chrome',
  card: 'bg-card',
  overlay: 'bg-overlay border border-line-strong',
}

/** A surface at one of the four named levels. Never a drop shadow. */
export function Surface({
  level = 'card',
  className,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & { level?: Level }) {
  return (
    <div {...props} className={cx('rounded-xl', levels[level], className)}>
      {children}
    </div>
  )
}

/**
 * A chrome strip — the header or the composer.
 *
 * `edge` puts the hairline on the side facing the conversation, so the well
 * reads as inset between them rather than as one flat sheet.
 */
export function Bar({
  edge,
  className,
  children,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & { edge: 'bottom' | 'top' }) {
  return (
    <div
      {...props}
      className={cx(
        'shrink-0 bg-chrome',
        edge === 'bottom' ? 'border-b border-line' : 'border-t border-line',
        className,
      )}
    >
      {children}
    </div>
  )
}
