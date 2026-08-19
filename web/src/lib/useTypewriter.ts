import { useCallback, useEffect, useRef, useState } from 'react'

/**
 * Draws streamed text at a continuous rate.
 *
 * The CLI does not stream word by word. It coalesces the model's deltas and
 * emits a paragraph in about five chunks, roughly a second apart. Drawing each
 * chunk as it lands gives a burst, then a stall, then a burst.
 *
 * So the text is treated as a reservoir drained at a steady speed, rather than
 * copied out as it arrives. The speed adapts to how much is waiting, but it
 * changes gradually and the loop keeps running while the answer is in flight,
 * so it never snaps to a halt between chunks.
 *
 * This deliberately draws behind: the display trails the data by a fraction of
 * a second, which is what buys the smoothness. The trade is only visual — the
 * answer takes exactly as long to arrive either way, and `flush` drops the
 * remainder in immediately when the run ends.
 */

/** Slowest we ever draw, so a trickle still moves. */
const MIN_CHARS_PER_SECOND = 18
/** Fastest, so a long paste does not flash past unread. */
const MAX_CHARS_PER_SECOND = 1400
/** Aim to empty the reservoir over about this long. */
const TARGET_DRAIN_SECONDS = 1.1
/** How quickly the speed adapts. Low keeps changes gradual. */
const SMOOTHING = 0.1

export function useTypewriter() {
  const [shown, setShown] = useState('')
  const pending = useRef('')
  const active = useRef(false)
  const frame = useRef<number | null>(null)
  const rate = useRef(MIN_CHARS_PER_SECOND)
  const lastAt = useRef(0)
  /** Fractional characters carried between frames, so slow rates still move. */
  const carry = useRef(0)

  const stop = () => {
    if (frame.current !== null) cancelAnimationFrame(frame.current)
    frame.current = null
    lastAt.current = 0
    carry.current = 0
  }

  const tick = useCallback((now: number) => {
    const previous = lastAt.current || now
    // Clamped: a background tab can hand back a huge gap, which would dump the
    // whole reservoir in one frame.
    const elapsed = Math.min((now - previous) / 1000, 0.1)
    lastAt.current = now

    const waiting = pending.current.length
    const desired = Math.min(
      Math.max(waiting / TARGET_DRAIN_SECONDS, MIN_CHARS_PER_SECOND),
      MAX_CHARS_PER_SECOND,
    )
    rate.current += (desired - rate.current) * SMOOTHING

    carry.current += rate.current * elapsed
    const count = Math.floor(carry.current)

    if (count > 0 && waiting > 0) {
      carry.current -= count
      const piece = pending.current.slice(0, count)
      pending.current = pending.current.slice(count)
      setShown((text) => text + piece)
    }

    // Keep running while the answer is in flight even with nothing to draw.
    // Stopping here and restarting on the next chunk is what produced the
    // start-stop stutter.
    if (active.current || pending.current) {
      frame.current = requestAnimationFrame(tick)
    } else {
      stop()
    }
  }, [])

  const start = useCallback(() => {
    if (frame.current === null) frame.current = requestAnimationFrame(tick)
  }, [tick])

  const push = useCallback(
    (text: string) => {
      pending.current += text
      start()
    },
    [start],
  )

  /** Marks the run as in flight, so the loop keeps ticking through the gaps. */
  const setActive = useCallback(
    (value: boolean) => {
      active.current = value
      if (value) {
        rate.current = MIN_CHARS_PER_SECOND
        start()
      }
    },
    [start],
  )

  const reset = useCallback(() => {
    active.current = false
    stop()
    pending.current = ''
    rate.current = MIN_CHARS_PER_SECOND
    setShown('')
  }, [])

  /** Everything received, drawn at once. Used when the run ends. */
  const flush = useCallback(() => {
    active.current = false
    stop()
    setShown((text) => text + pending.current)
    pending.current = ''
  }, [])

  useEffect(() => stop, [])

  return { shown, push, reset, flush, setActive }
}
