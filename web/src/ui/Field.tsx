/**
 * Label, control, hint — one spacing rule.
 *
 * The settings form drifted because each row chose its own gaps and label
 * weight. Routing every row through here is what keeps them aligned.
 */
export function Field({
  label,
  hint,
  htmlFor,
  children,
}: {
  label: string
  hint?: React.ReactNode
  htmlFor?: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <label htmlFor={htmlFor} className="block text-sm font-medium text-ink">
        {label}
      </label>
      {children}
      {hint && <p className="text-xs leading-relaxed text-muted">{hint}</p>}
    </div>
  )
}
