/// Where a hotspot is in the crew workflow.
public enum HotspotStatus: String, CaseIterable, Sendable {
    case new, assigned, extinguished, verifiedCold, flaredUp
}

/// Something that moves a hotspot through its workflow.
public enum HotspotAction: String, CaseIterable, Sendable {
    /// A crew member takes the hotspot.
    case assign
    /// The crew member hands it back.
    case unassign
    /// The crew reports it put out.
    case extinguish
    /// A later check confirms it is cold.
    case verifyCold
    /// A drone measured it hot again after it was put out. Issued by detection, not crews.
    case flareUp
}

/// The workflow state of one hotspot: a small state machine.
///
/// ```
/// new ──assign──► assigned ──extinguish──► extinguished ──verifyCold──► verifiedCold
///  ▲                │  ▲                       │                            │
///  └────unassign────┘  └──assign── flaredUp ◄──┴────────── flareUp ─────────┘
/// ```
/// `extinguish` is also allowed straight from `new` or `flaredUp`, for crews that
/// put a hotspot out without claiming it first.
public struct HotspotWorkflow: Hashable, Sendable {
    public private(set) var status: HotspotStatus
    /// How many times the hotspot has flared up.
    public private(set) var flareUps: Int

    public static let initial = HotspotWorkflow(status: .new, flareUps: 0)

    private init(status: HotspotStatus, flareUps: Int) {
        self.status = status
        self.flareUps = flareUps
    }

    public func canApply(_ action: HotspotAction) -> Bool {
        (try? applying(action)) != nil
    }

    /// The workflow after `action`.
    /// - Throws: ``WorkflowError`` when `action` isn't allowed from the current status.
    public func applying(_ action: HotspotAction) throws(WorkflowError) -> HotspotWorkflow {
        switch (action, status) {
        case (.assign, .new), (.assign, .flaredUp):
            return with(.assigned)
        case (.unassign, .assigned):
            return with(flareUps == 0 ? .new : .flaredUp)
        case (.extinguish, .new), (.extinguish, .assigned), (.extinguish, .flaredUp):
            return with(.extinguished)
        case (.verifyCold, .extinguished):
            return with(.verifiedCold)
        case (.flareUp, .extinguished), (.flareUp, .verifiedCold):
            return HotspotWorkflow(status: .flaredUp, flareUps: flareUps + 1)
        default:
            throw WorkflowError(action: action, status: status)
        }
    }

    private func with(_ status: HotspotStatus) -> HotspotWorkflow {
        HotspotWorkflow(status: status, flareUps: flareUps)
    }
}

/// An action that isn't allowed from the hotspot's current status.
public struct WorkflowError: Error, Hashable, Sendable {
    public let action: HotspotAction
    public let status: HotspotStatus
}
