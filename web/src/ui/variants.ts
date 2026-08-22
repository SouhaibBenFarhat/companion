/**
 * Every variant the kit offers, as data.
 *
 * A closed union per prop, so a typo is a compile error rather than a class
 * name that silently does nothing. And a table rather than a chain of
 * conditionals, so adding a tone means adding a row.
 *
 * No hover or active values here. Those come from the surface an element sits
 * on, in base.css, which is what stops a hover ever matching its background.
 */

export type Size = 'xs' | 'sm' | 'md'
export type Tone = 'neutral' | 'accent' | 'danger'
export type Variant = 'filled' | 'outlined' | 'ghost'

/** One height scale for everything, so a row of mixed controls lines up. */
export const height: Record<Size, string> = {
  xs: 'h-[var(--h-xs)]',
  sm: 'h-[var(--h-sm)]',
  md: 'h-[var(--h-md)]',
}

export const square: Record<Size, string> = {
  xs: 'h-[var(--h-xs)] w-[var(--h-xs)]',
  sm: 'h-[var(--h-sm)] w-[var(--h-sm)]',
  md: 'h-[var(--h-md)] w-[var(--h-md)]',
}

/** Text size follows height rather than being chosen separately. */
export const textSize: Record<Size, string> = {
  xs: 'text-xs',
  sm: 'text-sm',
  md: 'text-md',
}

/**
 * Resting appearance only.
 *
 * `filled` sets its own surface variable so its hover steps from its own
 * colour rather than from whatever is behind it.
 */
export const appearance: Record<Variant, Record<Tone, string>> = {
  filled: {
    neutral: 'bg-control text-ink [--surface:var(--s-4)]',
    accent: 'bg-accent text-accent-fg font-medium [--surface:var(--a-fill)]',
    danger: 'bg-danger text-accent-fg font-medium [--surface:var(--d-fill)]',
  },
  outlined: {
    neutral: 'bg-control text-ink border border-line-strong [--surface:var(--s-4)]',
    accent: 'bg-accent-soft text-accent-text border border-accent-line [--surface:var(--a-soft)]',
    danger: 'bg-danger-soft text-danger-text border border-danger-line [--surface:var(--d-soft)]',
  },
  ghost: {
    neutral: 'text-muted',
    accent: 'text-accent-text',
    danger: 'text-danger-text',
  },
}

/**
 * Pressed is a state a control holds, not a hover.
 *
 * A tint, never a surface step. In the light ramp every surface above the
 * chrome is pure white — s-4, s-5 and s-6 are all 100% — so a held control
 * that raised itself a step had nothing to raise itself against, and the lit
 * button in the header was invisible. A tint separates on hue as well as
 * lightness, which works in both appearances.
 */
export const pressed: Record<Tone, string> = {
  neutral: 'bg-accent-soft text-accent-text [--surface:var(--a-soft)]',
  accent: 'bg-accent-soft text-accent-text [--surface:var(--a-soft)]',
  danger: 'bg-danger-soft text-danger-text [--surface:var(--d-soft)]',
}

export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ')
}
