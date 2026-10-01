import Testing

@testable import FireWatchCore

struct HotspotWorkflowTests {
    func workflow(after actions: HotspotAction...) throws -> HotspotWorkflow {
        try actions.reduce(HotspotWorkflow.initial) { try $0.applying($1) }
    }

    @Test func fullMopUpCycle() throws {
        let done = try workflow(after: .assign, .extinguish, .verifyCold)
        #expect(done.status == .verifiedCold)
        #expect(done.flareUps == 0)
    }

    @Test func flareUpStartsNewCycle() throws {
        let flared = try workflow(after: .assign, .extinguish, .verifyCold, .flareUp)
        #expect(flared.status == .flaredUp)
        #expect(flared.flareUps == 1)

        let again = try workflow(after: .extinguish, .flareUp, .assign, .extinguish, .flareUp)
        #expect(again.flareUps == 2)
    }

    @Test func unassignReturnsToUnclaimedStatusOfTheCycle() throws {
        #expect(try workflow(after: .assign, .unassign).status == .new)
        #expect(try workflow(after: .extinguish, .flareUp, .assign, .unassign).status == .flaredUp)
    }

    @Test func extinguishWithoutClaiming() throws {
        #expect(try workflow(after: .extinguish).status == .extinguished)
        #expect(try workflow(after: .extinguish, .flareUp, .extinguish).status == .extinguished)
    }

    /// Every (status, action) pair not in the diagram is rejected.
    @Test func illegalTransitionsThrow() throws {
        let legal: [HotspotStatus: Set<HotspotAction>] = [
            .new: [.assign, .extinguish],
            .assigned: [.unassign, .extinguish],
            .extinguished: [.verifyCold, .flareUp],
            .verifiedCold: [.flareUp],
            .flaredUp: [.assign, .extinguish],
        ]
        let reachable: [HotspotStatus: HotspotWorkflow] = [
            .new: .initial,
            .assigned: try workflow(after: .assign),
            .extinguished: try workflow(after: .extinguish),
            .verifiedCold: try workflow(after: .extinguish, .verifyCold),
            .flaredUp: try workflow(after: .extinguish, .flareUp),
        ]
        for (status, state) in reachable {
            for action in HotspotAction.allCases {
                let allowed = legal[status, default: []].contains(action)
                #expect(state.canApply(action) == allowed, "\(action) from \(status)")
                if !allowed {
                    #expect(throws: WorkflowError(action: action, status: status)) {
                        try state.applying(action)
                    }
                }
            }
        }
    }
}
