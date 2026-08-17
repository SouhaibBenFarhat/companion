import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import rehypeHighlight from 'rehype-highlight'

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
      >
        {text}
      </ReactMarkdown>
    </div>
  )
}
