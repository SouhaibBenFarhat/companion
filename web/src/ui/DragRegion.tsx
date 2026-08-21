import { send } from '../lib/bridge'

/** Below this much movement, a press counts as a click rather than a drag. */
const SLOP = 4

/**
 * Makes an area move the window.
 *
 * `-webkit-app-region: drag` is an Electron feature and does nothing in a
 * WKWebView, and the web view swallows the mouse events AppKit would use. So
 * the region reports movement and Swift moves the panel. Screen coordinates,
 * because they do not shift as the window follows the pointer.
 *
 * A control inside a drag region keeps its own `onClick`. That matters for two
 * reasons: the click fires for the keyboard as well as the mouse, and only one
 * drag session starts per press. Doing the click from here instead meant the
 * button's own mousedown AND the strip's mousedown each started a session, so
 * the window moved twice as far as the pointer — and Tab plus Enter did nothing
 * at all, because no mousedown ever happened.
 *
 * When the press really did drag, the click that follows is swallowed, so
 * letting go over a button does not also press it.
 */
export function startDrag(event: React.MouseEvent): void {
  if (event.button !== 0) return

  // The innermost region owns the press. Without this the strip underneath
  // starts a second session on the same event.
  event.stopPropagation()
  event.preventDefault()

  let lastX = event.screenX
  let lastY = event.screenY
  let travelled = 0

  const previousCursor = document.body.style.cursor
  document.body.style.cursor = 'grabbing'

  const move = (e: MouseEvent) => {
    const dx = e.screenX - lastX
    const dy = e.screenY - lastY
    lastX = e.screenX
    lastY = e.screenY
    if (dx === 0 && dy === 0) return
    travelled += Math.abs(dx) + Math.abs(dy)
    send({ type: 'drag', dx, dy })
  }

  const stop = () => {
    window.removeEventListener('mousemove', move)
    window.removeEventListener('mouseup', stop)
    document.body.style.cursor = previousCursor

    if (travelled < SLOP) return
    // Dropping the window over a button must not press it. One capture-phase
    // listener, removed by its own `once`, so nothing outlives the drag.
    window.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation() }, {
      capture: true,
      once: true,
    })
  }

  window.addEventListener('mousemove', move)
  window.addEventListener('mouseup', stop)
}

/** Wraps children in an area that moves the window. */
export function DragRegion({
  children,
  ...props
}: Omit<React.HTMLAttributes<HTMLDivElement>, 'className'> & { children: React.ReactNode }) {
  return (
    <div onMouseDown={startDrag} className="cursor-grab active:cursor-grabbing" {...props}>
      {children}
    </div>
  )
}

/** A visible hint that an area can be grabbed. */
export function GrabHandle() {
  return (
    <div
      aria-hidden="true"
      className="absolute inset-x-0 top-2.5 mx-auto h-1 w-9 rounded-full bg-grab transition-colors group-hover:bg-grab-hover"
    />
  )
}
