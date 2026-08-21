import {
  appearance,
  cx,
  pressed as pressedTone,
  square,
  type Size,
  type Tone,
  type Variant,
} from './variants'

type NativeButton = Omit<React.ComponentPropsWithRef<'button'>, 'className' | 'aria-label' | 'title'>

/**
 * An icon-only button.
 *
 * `label` is required. An icon with no accessible name is invisible to anything
 * not looking at it, and it doubles as the macOS tooltip — which is why the kit
 * ships no Tooltip component. The system one is real, delayed correctly, and is
 * one fewer floating surface to dismiss in a panel where dismissal is the thing
 * that keeps breaking.
 */
export function IconButton({
  label,
  size = 'sm',
  tone = 'neutral',
  variant = 'ghost',
  pressed = false,
  badge = false,
  busy = false,
  children,
  ...props
}: NativeButton & {
  label: string
  size?: Size
  tone?: Tone
  variant?: Variant
  /** A state the control holds, like listening. Not a hover. */
  pressed?: boolean
  /** A dot, for a setting that changes behaviour and is otherwise invisible. */
  badge?: boolean
  /** Work in flight. Pulses rather than spinning — it is 14 points wide. */
  busy?: boolean
}) {
  return (
    <button
      type="button"
      data-pressable
      data-pressed={pressed}
      aria-label={label}
      aria-pressed={pressed}
      title={label}
      {...props}
      className={cx(
        'relative grid shrink-0 place-items-center rounded-md',
        square[size],
        pressed ? pressedTone[tone] : appearance[variant][tone],
        busy && 'animate-pulse',
      )}
    >
      {children}
      {badge && (
        <span
          aria-hidden="true"
          className="absolute right-0.5 top-0.5 h-1.5 w-1.5 rounded-full bg-accent"
        />
      )}
    </button>
  )
}
