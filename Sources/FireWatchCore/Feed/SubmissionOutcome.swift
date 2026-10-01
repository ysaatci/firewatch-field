/// What happened to a command or report that was accepted.
public enum SubmissionOutcome: String, Hashable, Sendable {
    /// Applied now.
    case applied
    /// Already applied earlier; this was a retry.
    case duplicate
}
