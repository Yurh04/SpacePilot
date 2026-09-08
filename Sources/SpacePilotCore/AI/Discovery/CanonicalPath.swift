import Foundation

public extension URL {
    /// The canonical form of a filesystem URL used for identity and
    /// deduplication across AI discovery.
    ///
    /// Symbolic links are resolved *first* and the lexical form (`.`/`..`
    /// components, trailing slashes) is standardized *afterwards*. Order matters
    /// for paths that mix `..` with a symlink: resolving the real links before
    /// collapsing `..` yields the physically correct location, whereas
    /// collapsing `..` first can step across a link and name a different file.
    /// Every keyed comparison in discovery must agree on one order, and this is
    /// the same order the stable record IDs already use, so logically identical
    /// paths always collapse to one entry.
    ///
    /// This is a pure lexical/symlink normalization; it does not require the
    /// path to exist and never touches file contents.
    var canonicalizedForDiscovery: URL {
        resolvingSymlinksInPath().standardizedFileURL
    }

    /// The canonical discovery path as a string. Convenience for the common case
    /// of using the canonical location as a dictionary/set key.
    var canonicalizedDiscoveryPath: String {
        canonicalizedForDiscovery.path
    }
}
