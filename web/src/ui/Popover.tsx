import { useEffect } from 'react'
import { Popover as RadixPopover } from 'radix-ui'

/**
 * A panel anchored to a trigger.
 *
 * Used for the confirmation before letting the agent write to a repo — which
 * before this could not be dismissed by Escape or by clicking away, because it
 * was a bare absolutely-positioned div with no behaviour at all.
 *
 * Shares its internals with Menu, so it costs well under a kilobyte more.
 */
export function Popover({
  open,
  onOpenChange,
  trigger,
  children,
  align = 'start',
  width = 240,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  trigger: React.ReactNode
  children: React.ReactNode
  align?: 'start' | 'center' | 'end'
  width?: number
}) {
  // Same reason as Menu: a nonactivating panel gets no pointer event when you
  // click another app, so nothing else would ever close this.
  useEffect(() => {
    if (!open) return
    const close = () => onOpenChange(false)
    window.addEventListener('blur', close)
    return () => window.removeEventListener('blur', close)
  }, [open, onOpenChange])

  return (
    <RadixPopover.Root open={open} onOpenChange={onOpenChange} modal={false}>
      <RadixPopover.Trigger asChild>{trigger}</RadixPopover.Trigger>

      <RadixPopover.Portal>
        <RadixPopover.Content
          data-surface="overlay"
          side="top"
          align={align}
          sideOffset={6}
          collisionPadding={8}
          onEscapeKeyDown={(event) => event.stopPropagation()}
          style={{ zIndex: 'var(--z-float)' as unknown as number, width }}
          className="rounded-lg border border-line-strong p-3 outline-none"
        >
          {children}
        </RadixPopover.Content>
      </RadixPopover.Portal>
    </RadixPopover.Root>
  )
}
