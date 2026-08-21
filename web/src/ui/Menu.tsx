import { useEffect } from 'react'
import { DropdownMenu } from 'radix-ui'
import { CheckIcon } from './icons'

/**
 * A dropdown menu.
 *
 * Radix rather than hand-rolled. This was written by hand twice — once in the
 * agent picker and once in the history list — and both were wrong in the same
 * way: no arrow keys, no focus moving into the menu, no focus returning to the
 * trigger. Radix brings roving focus, typeahead, Home and End, the right ARIA
 * roles, and collision handling.
 *
 * Four settings below are required, not preferences. Each one is a bug that
 * already happened or would.
 */

/** Closes the menu when the panel loses focus.
 *
 *  Radix cannot do this. The panel is a nonactivating NSPanel, so clicking
 *  another app sends no pointer event to the document — `onPointerDownOutside`
 *  never fires and the menu stays open over whatever you switched to. The same
 *  latch bug was fixed once already in the sibling app. */
function useCloseOnBlur(open: boolean, close: () => void) {
  useEffect(() => {
    if (!open) return
    window.addEventListener('blur', close)
    return () => window.removeEventListener('blur', close)
  }, [open, close])
}

export function Menu({
  open,
  onOpenChange,
  trigger,
  children,
  align = 'start',
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  trigger: React.ReactNode
  children: React.ReactNode
  align?: 'start' | 'center' | 'end'
}) {
  useCloseOnBlur(open, () => onOpenChange(false))

  return (
    <DropdownMenu.Root
      open={open}
      onOpenChange={onOpenChange}
      // Modal mode sets `document.body.style.pointerEvents = 'none'` and
      // restores it from one module-level variable. Two overlapping layers and
      // the page is permanently dead to clicks — in a browser you reload, but
      // this panel is borderless with no address bar, so the app has to be
      // quit. There is nothing to gain either: the body already never scrolls.
      modal={false}
    >
      <DropdownMenu.Trigger asChild>{trigger}</DropdownMenu.Trigger>

      <DropdownMenu.Portal>
        <DropdownMenu.Content
          data-surface="overlay"
          side="top"
          align={align}
          sideOffset={6}
          // Radix only knows the rectangular viewport. The visible rounded
          // corner is an AppKit mask it cannot see, and the panel resizes down
          // to 320 by 240 where a long list would run off the bottom.
          collisionPadding={8}
          // The panel listens for Escape on `window` to hide itself. Radix
          // listens on `document` in the capture phase, so without this one
          // press closes the menu AND the whole panel.
          onEscapeKeyDown={(event) => event.stopPropagation()}
          // Returning focus to a small chevron is wrong in a chat panel.
          onCloseAutoFocus={(event) => event.preventDefault()}
          // z-index goes on Content, never a wrapper: Radix inserts its own
          // positioning div that cannot be given a class, and copies the
          // computed stacking level from here at mount.
          style={{
            zIndex: 'var(--z-float)' as unknown as number,
            maxHeight: 'var(--radix-dropdown-menu-content-available-height)',
          }}
          className="min-w-[var(--menu-w)] overflow-y-auto rounded-lg border border-line-strong p-1"
        >
          {children}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  )
}

/** A row. Renders the tick itself so every menu aligns the same way. */
export function MenuItem({
  onSelect,
  selected = false,
  icon,
  label,
  detail,
  trailing,
  tone = 'neutral',
}: {
  onSelect: () => void
  selected?: boolean
  icon?: React.ReactNode
  label: string
  /** A second line. A name with no meaning is not a choice. */
  detail?: string
  trailing?: React.ReactNode
  tone?: 'neutral' | 'danger'
}) {
  return (
    <DropdownMenu.Item
      data-pressable
      onSelect={onSelect}
      className="flex w-full items-start gap-2 rounded-md px-2 py-1.5 text-left outline-none"
    >
      <span className="mt-0.5 w-3 shrink-0">
        {selected ? <CheckIcon size={12} strokeWidth={2.5} className="text-accent-text" /> : icon}
      </span>

      <span className="min-w-0 flex-1">
        <span className={`block text-sm font-medium ${tone === 'danger' ? 'text-danger-text' : 'text-ink'}`}>
          {label}
        </span>
        {detail && <span className="block text-xs leading-snug text-muted">{detail}</span>}
      </span>

      {trailing && <span className="ml-2 shrink-0 text-xs text-muted">{trailing}</span>}
    </DropdownMenu.Item>
  )
}

export function MenuDivider() {
  return <DropdownMenu.Separator className="my-1 h-px" style={{ background: 'var(--c-line)' }} />
}
