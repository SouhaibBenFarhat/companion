import { cx, focusRing } from './styles'

/// A switch for something that is either on or off.
///
/// A checkbox reads as "tick this to agree". A switch reads as "this is
/// running", which is what a capture setting actually is.
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
    <label
      className={cx(
        'flex cursor-pointer gap-3',
        hint ? 'items-start' : 'items-center gap-2',
        disabled && 'cursor-not-allowed opacity-50',
      )}
    >
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cx(
          'relative mt-0.5 h-[18px] w-[30px] shrink-0 rounded-full transition-colors',
          checked ? 'bg-accent' : 'bg-control-active',
          focusRing,
        )}
      >
        <span
          className={cx(
            'absolute top-[2px] h-[14px] w-[14px] rounded-full bg-white transition-[left] duration-150',
            checked ? 'left-[14px]' : 'left-[2px]',
          )}
        />
      </button>

      <span className="min-w-0 flex-1">
        <span className={cx('block font-medium text-ink', hint ? 'text-[12px]' : 'text-[11px]')}>{label}</span>
        {hint && <span className="mt-0.5 block text-[11px] leading-relaxed text-muted">{hint}</span>}
      </span>
    </label>
  )
}
