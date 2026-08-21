import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import rehypeHighlight from 'rehype-highlight'
import { send } from '../lib/bridge'

/** Anything else — file:, data:, javascript: — is not a link we will open. */
const OPENABLE = /^https?:\/\//i

/**
 * Renders an answer.
 *
 * `react-markdown` rather than setting innerHTML: the text comes from a
 * subprocess reading files off disk, and building the DOM from a parsed tree
 * means a stray tag in someone's source file can never become live markup.
 */
export function Markdown({ text }: { text: string }) {
  return (
    <div className="prose selectable break-words">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[[rehypeHighlight, { detect: true, ignoreMissing: true }]]}
        components={{
          // A link used to navigate the panel itself. There is no address bar
          // and no back button in a borderless window, so the conversation was
          // simply gone — the only way back was to quit the app. Links go to
          // the real browser now, and anything that is not http(s) is inert.
          a: ({ href, children }) => (
            <a
              href={href}
              onClick={(event) => {
                event.preventDefault()
                if (href && OPENABLE.test(href)) send({ type: 'openLink', url: href })
              }}
            >
              {children}
            </a>
          ),
        }}
      >
        {text}
      </ReactMarkdown>
    </div>
  )
}
