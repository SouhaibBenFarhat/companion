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
 *
 * `label` is a NAME — "Send", "History". When the tooltip needs to say more
 * than the name, that goes in `hint`; the accessible name must not turn into a
 * status sentence, or a screen reader announces "Microphone access is off,
 * button" instead of telling the user what the control is.
 */
export function IconButton({
  label,
  hint,
  size = 'sm',
  tone = 'neutral',
  activeTone,
  variant = 'ghost',
  pressed,
  badge = false,
  busy = false,
  children,
  ...props
}: NativeButton & {
  label: string
  /** Extra words for the tooltip only. Never part of the accessible name. */
  hint?: string
  size?: Size
  /** The resting look. Grey unless the control is meaningful at rest. */
  tone?: Tone
  /** The look while held on. Defaults to `tone`. */
  activeTone?: Tone
  variant?: Variant
  /**
   * A state the control holds, like listening. Leave it out entirely for a
   * one-shot action: `aria-pressed` on Send would announce it as a switch that
   * is currently off.
   */
  pressed?: boolean
  /** A dot, for a setting that changes behaviour and is otherwise invisible. */
  badge?: boolean
  /** Work in flight. Pulses rather than spinning — it is 14 points wide. */
  busy?: boolean
}) {
  const isOn = pressed === true

  return (
    <button
      type="button"
      data-pressable
      data-pressed={isOn}
      aria-label={label}
      aria-pressed={pressed}
      title={hint ?? label}
      {...props}
      className={cx(
        'relative grid shrink-0 place-items-center rounded-md',
        square[size],
        isOn ? pressedTone[activeTone ?? tone] : appearance[variant][tone],
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
