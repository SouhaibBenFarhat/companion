import { cx } from './variants'

/**
 * A switch.
 *
 * A checkbox reads as "tick this to agree". A switch reads as "this is
 * running", which is what a capture setting actually is.
 *
 * Hand-built rather than taken from Radix: a `<button role="switch">` already
 * gets Space and Enter from the platform, so there is nothing to gain.
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
  return (
    <label className={cx('flex gap-3', hint ? 'items-start' : 'items-center gap-2')}>
      <button
        type="button"
        role="switch"
        data-pressable
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cx(
          'relative mt-0.5 h-[var(--switch-h)] w-[var(--switch-w)] shrink-0 rounded-full',
          checked ? 'bg-accent [--surface:var(--a-fill)]' : 'bg-control [--surface:var(--s-4)]',
        )}
      >
        <span
          className={cx(
            'absolute top-[var(--switch-gap)] h-[var(--switch-knob)] w-[var(--switch-knob)] rounded-full transition-[left]',
            checked ? 'left-[var(--switch-travel)]' : 'left-[var(--switch-gap)]',
          )}
          style={{ background: 'var(--on-fill)' }}
        />
      </button>

      <span className="min-w-0 flex-1">
        <span className={cx('block font-medium text-ink', hint ? 'text-sm' : 'text-xs')}>{label}</span>
        {hint && <span className="mt-0.5 block text-xs leading-relaxed text-muted">{hint}</span>}
      </span>
    </label>
  )
}
