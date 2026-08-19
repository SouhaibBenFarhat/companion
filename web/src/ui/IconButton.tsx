import { cx, disabled, focusRing } from './styles'

/**
 * Square icon-only button.
 *
 * `label` is required: an icon with no accessible name is invisible to
 * anything that isn't looking at it, and it doubles as the tooltip.
 */
export function IconButton({
  label,
  size = 'md',
  active = false,
  className,
  children,
  ...props
}: Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label'> & {
  label: string
  size?: 'sm' | 'md'
  active?: boolean
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      {...props}
      className={cx(
        'grid shrink-0 place-items-center rounded-md transition-colors',
        size === 'sm' ? 'h-6 w-6' : 'h-7 w-7',
        active
          ? 'bg-control-active text-ink'
          : 'text-muted hover:bg-control-hover hover:text-ink active:bg-control-active',
        focusRing,
        disabled,
        className,
      )}
    >
      {children}
    </button>
  )
}
