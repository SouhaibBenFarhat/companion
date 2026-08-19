import type { Incoming, Outgoing } from './types'

declare global {
  interface Window {
    __companion?: { receive: (payload: Incoming) => void }
    webkit?: {
      messageHandlers?: {
        companion?: { postMessage: (message: unknown) => void }
      }
    }
  }
}

/**
 * Page to Swift.
 *
 * Outside the app — running `npm run dev` in a normal browser — there is no
 * native side, so messages are logged instead. That keeps the UI workable on
 * its own rather than throwing on every click.
 */
export function send(message: Outgoing): void {
  const handler = window.webkit?.messageHandlers?.companion
  if (handler) {
    handler.postMessage(message)
  } else {
    console.info('[companion] no native bridge:', message)
  }
}

/** Swift to page. Swift calls `window.__companion.receive(...)`. */
export function listen(handler: (payload: Incoming) => void): () => void {
  window.__companion = { receive: handler }
  return () => {
    delete window.__companion
  }
}

/** Below this much movement, a press counts as a click rather than a drag. */
const DRAG_SLOP = 4

/**
 * Window dragging.
 *
 * `-webkit-app-region: drag` is an Electron feature and does nothing in a
 * WKWebView, and the web view swallows the mouse events that would otherwise
 * let AppKit move the window. So drag surfaces report movement and Swift moves
 * the panel. Screen coordinates on purpose: they do not shift as the window
 * follows the pointer, which client coordinates would.
 *
 * @param onClick runs if the pointer barely moved, so a control can both drag
 *   the window and still act on a plain click. Without this, anything clickable
 *   has to opt out of dragging, which is what made the grab area so thin.
 */
export function startDrag(event: React.MouseEvent, onClick?: () => void): void {
  if (event.button !== 0) return
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
    if (travelled < DRAG_SLOP) onClick?.()
  }

  window.addEventListener('mousemove', move)
  window.addEventListener('mouseup', stop)
}
