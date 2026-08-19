import Foundation

/// Masks secrets before anything is written to disk.
///
/// Companion writes a rolling log and a file per conversation. Both can end up
/// holding whatever was on screen or in a prompt, and people paste logs into
/// issues. `~/Library` being private is not the control here — not writing the
/// secret down is.
///
/// The rule throughout: a false positive is cheap, a miss is not. But masking
/// ordinary code would make the log useless, so every pattern below is anchored
/// on something a secret has and normal text does not.
public enum Redaction {
    public static let mask = "«redacted»"

    private struct Pattern {
        let regex: NSRegularExpression
        /// Which capture group holds the secret. 0 means the whole match.
        let group: Int

        init(_ expression: String, group: Int = 0, options: NSRegularExpression.Options = []) {
            // These are fixed literals written here, so a failure is a
            // programming error rather than something to handle at runtime.
            regex = try! NSRegularExpression(pattern: expression, options: options)
            self.group = group
        }
    }

    private static let patterns: [Pattern] = [
        // Vendor keys, which all carry a recognisable prefix.
        Pattern(#"\b(sk|pk|rk)-[A-Za-z0-9_-]{16,}"#),
        Pattern(#"\bsk-ant-[A-Za-z0-9_-]{16,}"#),
        Pattern(#"\bgh[pousr]_[A-Za-z0-9]{16,}"#),
        Pattern(#"\bgithub_pat_[A-Za-z0-9_]{20,}"#),
        Pattern(#"\bxox[baprs]-[A-Za-z0-9-]{10,}"#),
        Pattern(#"\bAKIA[0-9A-Z]{16}\b"#),
        Pattern(#"\bAIza[0-9A-Za-z_-]{30,}"#),

        // Authorization headers.
        Pattern(#"(?i)\b(bearer|basic)\s+([A-Za-z0-9._~+/=-]{16,})"#, group: 2),

        // A whole private key block, header to footer.
        Pattern(
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#
        ),

        // JSON Web Tokens: three base64 segments separated by dots.
        Pattern(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#),

        // KEY=value where the name says it is a secret. Anchored on the name,
        // not the shape, so PATH= and HOME= are untouched.
        Pattern(
            #"(?i)\b[A-Z0-9_]*(?:SECRET|PASSWORD|PASSWD|TOKEN|APIKEY|API_KEY|ACCESS_KEY|PRIVATE_KEY|CREDENTIAL)[A-Z0-9_]*\s*[=:]\s*(\S+)"#,
            group: 1
        ),
    ]

    /// Replaces anything that looks like a credential.
    public static func scrub(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            result = apply(pattern, to: result)
        }
        return result
    }

    private static func apply(_ pattern: Pattern, to text: String) -> String {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = pattern.regex.matches(in: text, range: full)
        guard !matches.isEmpty else { return text }

        var result = text
        // Back to front, so earlier ranges stay valid as we edit.
        for match in matches.reversed() {
            let target = match.range(at: min(pattern.group, match.numberOfRanges - 1))
            guard target.location != NSNotFound, let range = Range(target, in: result) else { continue }
            result.replaceSubrange(range, with: mask)
        }
        return result
    }
}
