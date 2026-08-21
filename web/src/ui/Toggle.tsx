import { useId } from 'react'
import { cx } from './variants'

/**
 * A switch.
 *
 * A checkbox reads as "tick this to agree". A switch reads as "this is
 * running", which is what a capture setting actually is.
 *
 * Hand-built rather than taken from Radix: a `<button role="switch">` already
 * gets Space and Enter from the platform, so there is nothing to gain.
 *
 * The hint is deliberately outside the label. A `<label>` forwards its click to
 * the control inside it, so wrapping the explanation meant that reading what a
 * setting does — or dragging across it to copy it — flipped that setting.
 */
export function Toggle({
  checked,
  onChange,
  label,
  hint,
  disabled = false,
}: {
  checked: boolean
  onChange: (value: boolean) => void
  label: string
  hint?: string
  disabled?: boolean
}) {
  const id = useId()

  const control = (
    <button
      id={id}
      type="button"
      role="switch"
      data-pressable
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cx(
        'relative h-[var(--switch-h)] w-[var(--switch-w)] shrink-0 rounded-full',
        hint && 'mt-0.5',
        checked ? 'bg-accent [--surface:var(--a-fill)]' : 'bg-control [--surface:var(--s-4)]',
      )}
    >
      <span
        className={cx(
          'absolute top-[var(--switch-gap)] h-[var(--switch-knob)] w-[var(--switch-knob)] rounded-full transition-[left]',
          checked ? 'left-[var(--switch-travel)]' : 'left-[var(--switch-gap)]',
        )}
        style={{ background: 'var(--c-accent-fg)' }}
      />
    </button>
  )

  const title = (
    <label
      htmlFor={id}
      className={cx('block cursor-pointer font-medium text-ink', hint ? 'text-sm' : 'text-xs')}
    >
      {label}
    </label>
  )

  if (!hint) {
    return (
      <div className="flex items-center gap-2">
        {control}
        {title}
      </div>
    )
  }

  return (
    <div className="flex items-start gap-3">
      {control}
      <div className="min-w-0 flex-1">
        {title}
        <p className="mt-0.5 text-xs leading-relaxed text-muted">{hint}</p>
      </div>
    </div>
  )
}
