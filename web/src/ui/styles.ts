/**
 * Shared class fragments.
 *
 * Every control in the kit is built from these, so a focus ring or a disabled
 * state is defined once. Anything reaching for its own colours or radii is a
 * sign the kit is missing a component.
 */

/** Same focus treatment everywhere, keyboard only. */
export const focusRing =
  'outline-none focus-visible:ring-2 focus-visible:ring-accent/55 focus-visible:ring-offset-1 focus-visible:ring-offset-chrome'

export const disabled = 'disabled:pointer-events-none disabled:opacity-45'

/** Controls share one height scale so a row of them lines up. */
export const controlHeight = {
  sm: 'h-7',
  md: 'h-8',
} as const

export type Size = keyof typeof controlHeight

export const textSize: Record<Size, string> = {
  sm: 'text-[12px]',
  md: 'text-[13px]',
}

export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ')
}
