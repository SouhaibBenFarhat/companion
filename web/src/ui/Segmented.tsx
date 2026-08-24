import { appearance, cx, height, pressed, textSize, type Size } from './variants'

/**
 * One choice out of two or three, all visible at once.
 *
 * A Select hides the options behind a click, which is the wrong trade when the
 * labels are one word each and the choice is something you flip back and forth.
 *
 * Radio semantics, not buttons: a screen reader announces "Dark, radio button,
 * 2 of 3", which is what this is.
 */
export function Segmented<T extends string>({
  value,
  onChange,
  options,
  label,
  size = 'sm',
}: {
  value: T
  onChange: (value: T) => void
  options: ReadonlyArray<{ value: T; label: string }>
  label: string
  size?: Size
}) {
  return (
    <div
      role="radiogroup"
      aria-label={label}
      data-surface="input"
      className="inline-flex w-full gap-0.5 rounded-md p-0.5"
    >
      {options.map((option) => {
        const selected = option.value === value
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={selected}
            data-pressable
            data-pressed={selected}
            onClick={() => onChange(option.value)}
            className={cx(
              'flex-1 select-none rounded-sm px-2',
              height[size],
              textSize[size],
              selected ? `${pressed.neutral} font-medium` : appearance.ghost.neutral,
            )}
          >
            {option.label}
          </button>
        )
      })}
    </div>
  )
}
