import Foundation

/// Pure, deterministic ordering rules.
///
/// 1. Higher priority first.
/// 2. A user-pinned activity outranks `normal`/`low` (but never `high`/`critical`).
/// 3. Among equals, the incumbent (earliest arrival) stays in front — new arrivals never steal focus
///    from an activity of the same priority. This is what keeps the Island from constantly interrupting.
/// 4. Final tie-break on id so ordering is total.
public enum ActivityOrdering {
    public static func rank(_ a: Activity, pinnedID: String?) -> Int {
        var r = a.priority.rawValue * 2
        if a.id == pinnedID { r = max(r, ActivityPriority.normal.rawValue * 2 + 1) }
        return r
    }

    public static func sort(_ activities: [Activity], pinnedID: String?) -> [Activity] {
        activities.sorted { a, b in
            let ra = rank(a, pinnedID: pinnedID), rb = rank(b, pinnedID: pinnedID)
            if ra != rb { return ra > rb }
            if a.sequence != b.sequence { return a.sequence < b.sequence }
            return a.id < b.id
        }
    }
}
