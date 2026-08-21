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
