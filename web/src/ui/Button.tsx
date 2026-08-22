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
  flexible = false,
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
  /** May shrink and truncate. For a row that has to survive a 320pt panel. */
  flexible?: boolean
}) {
  const resolved: Tone = tone ?? (variant === 'filled' ? 'accent' : 'neutral')

  return (
    <button
      type="button"
      data-pressable
      data-pressed={pressed}
      {...props}
      className={cx(
        'inline-flex select-none items-center justify-center gap-1.5 rounded-md',
        flexible ? 'min-w-0 shrink' : 'shrink-0',
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
