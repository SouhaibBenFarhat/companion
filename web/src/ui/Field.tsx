import { cx } from './styles'

/**
 * Label, control, hint — in that order, with one spacing rule.
 *
 * The settings form drifted because each row picked its own gaps and label
 * weight. Routing every row through here is what keeps them aligned.
 */
export function Field({
  label,
  hint,
  htmlFor,
  children,
  className,
}: {
  label: string
  hint?: React.ReactNode
  htmlFor?: string
  children: React.ReactNode
  className?: string
}) {
  return (
    <div className={cx('space-y-1.5', className)}>
      <label htmlFor={htmlFor} className="block text-[12px] font-medium text-ink">
        {label}
      </label>
      {children}
      {hint && <p className="text-[11px] leading-relaxed text-muted">{hint}</p>}
    </div>
  )
}
