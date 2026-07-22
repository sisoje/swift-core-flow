/// Reads a value type's stored-property names without needing an instance — just
/// `T.self`. Pairs naturally with `@Flowable`: `Reflector.fieldNames(of:
/// Point.InFlow.self)` lists the same names `inFlow` returns values for.
///
/// Not a macro — a plain runtime utility, kept in this package because it's a small,
/// natural companion to `@Flowable`'s generated members rather than because it
/// needs code generation itself.
public enum Reflector {
    /// Allocates one uninitialized `T` and reads its stored-property labels via
    /// `Mirror` — no real instance required. This only works because `Mirror`'s
    /// labels come from `T`'s compile-time field metadata; it never needs to
    /// materialize/retain an actual child *value*, which is what would make reading
    /// uninitialized memory unsafe here (`fieldNames` never calls `.value` on a
    /// child, only `.label`).
    ///
    /// **Requires a value type.** Swift has no generic constraint for "not a class"
    /// (and tuples can't conform to a marker protocol to opt into one, so a
    /// protocol-based constraint couldn't cover both structs and tuples anyway) —
    /// so this is a runtime guard, not a compile-time one. Verified directly: a bare
    /// class as `T` crashes with a null-pointer trap inside `Mirror`'s
    /// `CustomReflectable` cast on the top-level value (the cast needs a valid
    /// reference before any field is inspected); this `precondition` turns that into
    /// a clear message instead. A struct or tuple containing a class-typed field is
    /// fine either way — the crash is about `T`'s own top-level kind, not its fields.
    public static func fieldNames<T>(of: T.Type) -> [String] {
        precondition(!(T.self is AnyClass), "fieldNames requires a value type, got class \(T.self)")
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { p.deallocate() }
        return Mirror(reflecting: p.pointee).children.compactMap(\.label)
    }
}
