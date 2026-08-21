import {
  appearance,
  cx,
  height,
  pressed as pressedTone,
  textSize,
  type Size,
  type Tone,
  type Variant,
} from './variants'

type NativeButton = Omit<React.ComponentPropsWithRef<'button'>, 'className'>

/**
 * A button.
 *
 * No `className`. In a stylesheet the source order decides the winner, not the
 * order of names in the class attribute, so a passed-in override silently did
 * nothing anyway. A view that wants spacing wraps this; a view that wants a
 * different look asks for a variant.
 *
 * Hover, active, focus and disabled are not here. They come from base.css,
 * derived from the surface this sits on.
 */
export function Button({
  variant = 'outlined',
  tone,
  size = 'sm',
  full = false,
  pressed = false,
  tight = false,
  children,
  ...props
}: NativeButton & {
  variant?: Variant
  tone?: Tone
  size?: Size
  full?: boolean
  /** Held open or armed — a state, not a hover. Also drives `aria-expanded`. */
  pressed?: boolean
  /** Narrow padding, for a button that sits in a row of icons. */
  tight?: boolean
}) {
  const resolved: Tone = tone ?? (variant === 'filled' ? 'accent' : 'neutral')

  return (
    <button
      type="button"
      data-pressable
      data-pressed={pressed}
      {...props}
      className={cx(
        'inline-flex shrink-0 select-none items-center justify-center gap-1.5 rounded-md',
        tight ? 'px-1.5' : 'px-3',
        height[size],
        textSize[size],
        pressed ? pressedTone[resolved] : appearance[variant][resolved],
        full && 'w-full',
      )}
    >
      {children}
    </button>
  )
}
