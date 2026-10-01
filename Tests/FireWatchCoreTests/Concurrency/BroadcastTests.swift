import TestSupport
import Testing

@testable import FireWatchCore

struct BroadcastTests {
    @Test func everySubscriberGetsEveryValue() async {
        let broadcast = Broadcast<Int>()
        let (_, first) = broadcast.subscribe()
        let (_, second) = broadcast.subscribe()
        broadcast.yield(1)
        broadcast.yield(2)
        #expect(await first.prefix(2).collect() == [1, 2])
        #expect(await second.prefix(2).collect() == [1, 2])
    }

    @Test func valuesCanTargetOneSubscriber() async {
        let broadcast = Broadcast<Int>()
        let (id, target) = broadcast.subscribe()
        let (_, other) = broadcast.subscribe()
        broadcast.yield(7, to: id)
        broadcast.yield(8)
        #expect(await target.prefix(2).collect() == [7, 8])
        #expect(await other.prefix(1).collect() == [8])
    }

    @Test func leavingSubscribersAreForgottenAndNotified() async {
        let broadcast = Broadcast<Int>()
        let left = Flag()
        do {
            let (_, stream) = broadcast.subscribe { Task { await left.set() } }
            #expect(broadcast.hasSubscribers)
            _ = stream  // dropped at the end of this scope
        }
        try? await eventually { await left.value }
        #expect(!broadcast.hasSubscribers)
    }

    actor Flag {
        var value = false
        func set() { value = true }
    }
}
