import { cx } from './styles'

/** A slow pulse, not a spinner — it sits beside text, not in a dialog. */
export function Pulse({ className }: { className?: string }) {
  return <span className={cx('inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-accent-text', className)} />
}

export function Hint({ className, children, ...props }: React.HTMLAttributes<HTMLParagraphElement>) {
  return (
    <p {...props} className={cx('text-[11px] leading-relaxed text-muted', className)}>
      {children}
    </p>
  )
}

export function Notice({
  tone = 'muted',
  className,
  children,
}: {
  tone?: 'muted' | 'danger'
  className?: string
  children: React.ReactNode
}) {
  return (
    <div
      className={cx(
        'selectable rounded-lg border px-3 py-2 text-[12px] leading-relaxed break-words',
        tone === 'danger'
          ? 'border-danger/35 bg-danger-soft text-danger'
          : 'border-line bg-card text-muted',
        className,
      )}
    >
      {children}
    </div>
  )
}
