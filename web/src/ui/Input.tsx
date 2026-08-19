import { cx, controlHeight, disabled, focusRing, textSize } from './styles'
import { ChevronIcon } from './icons'

const field =
  'w-full rounded-lg border border-line-strong bg-input px-2.5 text-ink transition-colors placeholder:text-muted hover:border-muted/60 focus:bg-input-focus'

export function Input({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      spellCheck={false}
      {...props}
      className={cx('selectable', field, controlHeight.md, textSize.md, focusRing, disabled, className)}
    />
  )
}

export function Textarea({ className, ...props }: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      spellCheck={false}
      {...props}
      className={cx(
        'selectable resize-none py-1.5 leading-relaxed',
        field,
        textSize.md,
        focusRing,
        disabled,
        className,
      )}
    />
  )
}

/**
 * Native select with the platform arrow replaced.
 *
 * The system control ignores the theme entirely — in dark mode it renders a
 * light box that belongs to no part of this panel.
 */
export function Select({ className, children, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <div className="relative">
      <select
        {...props}
        className={cx(
          'appearance-none pr-8',
          field,
          controlHeight.md,
          textSize.md,
          focusRing,
          disabled,
          className,
        )}
      >
        {children}
      </select>
      <ChevronIcon
        aria-hidden="true"
        size={13}
        strokeWidth={1.75}
        className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-muted"
      />
    </div>
  )
}
