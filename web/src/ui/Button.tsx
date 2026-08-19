import { cx, disabled, focusRing, controlHeight, textSize, type Size } from './styles'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'

const variants: Record<Variant, string> = {
  // Filled. One per view at most — the thing you actually want pressed.
  primary: 'bg-accent text-accent-fg hover:bg-accent-hover active:brightness-90 font-medium',
  // Bordered. Reads as a button standing still, which a plain label never does.
  secondary:
    'bg-control text-ink border border-line-strong hover:bg-control-hover active:bg-control-active',
  // No chrome until you touch it. For dense rows where borders would be noise.
  ghost: 'text-muted hover:bg-control-hover hover:text-ink active:bg-control-active',
  danger: 'text-danger hover:bg-danger-soft active:brightness-95',
}

export function Button({
  variant = 'secondary',
  size = 'md',
  full = false,
  className,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant
  size?: Size
  full?: boolean
}) {
  return (
    <button
      type="button"
      {...props}
      className={cx(
        'inline-flex shrink-0 items-center justify-center gap-1.5 rounded-lg px-3 transition-colors select-none',
        controlHeight[size],
        textSize[size],
        variants[variant],
        full && 'w-full',
        focusRing,
        disabled,
        className,
      )}
    />
  )
}
