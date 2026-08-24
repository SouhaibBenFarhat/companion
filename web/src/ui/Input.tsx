import { useEffect, useRef } from 'react'
import { cx } from './variants'
import { ChevronIcon } from './icons'

/** A recessed well. Things you press are raised; things you type into are not. */
const field =
  'w-full rounded-md border border-line-strong px-2.5 text-md text-ink placeholder:text-muted'

export function Input(props: Omit<React.InputHTMLAttributes<HTMLInputElement>, 'className'>) {
  return (
    <input
      data-field
      data-surface="input"
      spellCheck={false}
      {...props}
      className={cx('selectable h-[var(--h-md)]', field)}
    />
  )
}

export function Textarea(props: Omit<React.TextareaHTMLAttributes<HTMLTextAreaElement>, 'className'>) {
  return (
    <textarea
      data-field
      data-surface="input"
      spellCheck={false}
      {...props}
      className={cx('selectable resize-none py-1.5 leading-relaxed', field)}
    />
  )
}

/**
 * The native select with the platform arrow replaced.
 *
 * Native on purpose: the system popup scrolls, does typeahead, and costs
 * nothing. A built one would be the largest component in the kit for no gain.
 * Only the arrow is ours, because the system one ignores the theme entirely and
 * renders a light box in dark mode.
 */
export function Select({
  children,
  ...props
}: Omit<React.SelectHTMLAttributes<HTMLSelectElement>, 'className'>) {
  return (
    <div className="relative">
      <select
        data-field
        data-surface="input"
        {...props}
        className={cx('h-[var(--h-md)] appearance-none pr-8', field)}
      >
        {children}
      </select>
      <ChevronIcon
        aria-hidden="true"
        size={12}
        strokeWidth={2}
        className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted"
      />
    </div>
  )
}

/**
 * The container the composer's text area and its toolbar share.
 *
 * It pads nothing. Each section inside pads itself, so the divider between them
 * runs edge to edge instead of stopping short of the border.
 *
 * A recessed well, not another raised card: the field reads as a hole in the
 * chrome rather than a box sitting on top of it. `data-well` is what turns its
 * border accent when anything inside takes focus, so no view writes a focus
 * colour — and the field inside stays unmarked, or the composer gets two
 * rings.
 */
export function Well({ children }: { children: React.ReactNode }) {
  return (
    <div
      data-well
      data-surface="input"
      className="overflow-hidden rounded-lg border border-line-strong transition-colors"
    >
      {children}
    </div>
  )
}

/**
 * A text area that grows with what you type, up to a limit.
 *
 * The measuring trick — reset the height, read `scrollHeight`, set it back — is
 * the kind of thing that gets copied into the next multi-line field and drifts.
 * It lives here once, with the field it belongs to.
 *
 * `submit` fires on Enter; Shift+Enter still makes a new line.
 *
 * No `data-field`: this always sits inside a `Well`, and the well's border
 * already shows the focus. Marking both drew two rings around the composer.
 *
 * `ref` is destructured on purpose. React 19 passes it as an ordinary prop, so
 * leaving it in `...props` put the caller's ref after this one in the spread
 * and the internal ref stayed null — which killed Enter-to-send, the growing,
 * and focus-on-summon, all silently.
 */
export function AutoTextarea({
  min,
  max,
  submit,
  resetToken,
  ref,
  ...props
}: Omit<React.ComponentPropsWithRef<'textarea'>, 'className' | 'style' | 'onKeyDown'> & {
  min: number
  max: number
  submit: (text: string) => boolean
  /** Changes when the field should take focus again. */
  resetToken: unknown
}) {
  const element = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    element.current?.focus()
  }, [resetToken])

  const fit = () => {
    const field = element.current
    if (!field) return
    field.style.height = 'auto'
    field.style.height = `${Math.min(Math.max(field.scrollHeight, min), max)}px`
  }

  // Once, on mount: the field must open at its real height rather than
  // snapping to it on the first keystroke.
  useEffect(fit, [])

  return (
    <textarea
      spellCheck={false}
      {...props}
      ref={(node) => {
        element.current = node
        if (typeof ref === 'function') ref(node)
        // Never `return ref(node)` — React 19 reads a returned value as a
        // cleanup function.
        else if (ref) ref.current = node
      }}
      onInput={fit}
      onKeyDown={(event) => {
        if (event.key !== 'Enter' || event.shiftKey) return
        event.preventDefault()
        const field = element.current
        if (!field) return
        if (!submit(field.value.trim())) return
        field.value = ''
        fit()
      }}
      style={{ minHeight: min, maxHeight: max }}
      className="selectable block w-full resize-none bg-transparent px-0.5 text-md leading-relaxed text-ink outline-none placeholder:text-muted"
    />
  )
}
