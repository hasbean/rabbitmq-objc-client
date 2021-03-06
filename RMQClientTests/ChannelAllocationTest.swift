import XCTest

class ChannelAllocationTest: XCTestCase {
    let allocationsPerQueue = 30000

    func allocateAll(allocator: RMQChannelAllocator) {
        for _ in 1...RMQChannelLimit {
            allocator.allocate()
        }
    }

    func testChannelGetsNegativeOneChannelNumberWhenOutOfChannelNumbers() {
        let allocator = RMQMultipleChannelAllocator(channelSyncTimeout: 2)
        allocateAll(allocator)
        XCTAssertEqual(-1, allocator.allocate().channelNumber)
    }

    func testChannelGetsAFreedChannelNumberIfOtherwiseOutOfChannelNumbers() {
        let allocator = RMQMultipleChannelAllocator(channelSyncTimeout: 2)
        allocateAll(allocator)
        allocator.releaseChannelNumber(2)
        XCTAssertEqual(2, allocator.allocate().channelNumber)
        XCTAssertEqual(-1, allocator.allocate().channelNumber)
    }

    func testAllocatedChannelsCanBeRead() {
        let allocator = RMQMultipleChannelAllocator(channelSyncTimeout: 2)
        allocator.allocate()
        allocator.allocate()
        allocator.allocate()
        allocator.allocate()
        allocator.releaseChannelNumber(1)
        XCTAssertEqual([2, 3], allocator.allocatedUserChannels().map { $0.channelNumber })
    }

    func testNumbersAreNotDoubleAllocated() {
        let allocator   = RMQMultipleChannelAllocator(channelSyncTimeout: 2)
        var channelSet1 = Set<NSNumber>()
        var channelSet2 = Set<NSNumber>()
        var channelSet3 = Set<NSNumber>()
        let group       = dispatch_group_create()
        let queues      = [
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
        ]

        dispatch_group_async(group, queues[0]) {
            for _ in 1...self.allocationsPerQueue {
                channelSet1.insert(allocator.allocate().channelNumber)
            }
        }

        dispatch_group_async(group, queues[1]) {
            for _ in 1...self.allocationsPerQueue {
                channelSet2.insert(allocator.allocate().channelNumber)
            }
        }

        dispatch_group_async(group, queues[2]) {
            for _ in 1...self.allocationsPerQueue {
                channelSet3.insert(allocator.allocate().channelNumber)
            }
        }

        XCTAssertEqual(0, dispatch_group_wait(group, TestHelper.dispatchTimeFromNow(10)), "Timed out waiting for allocations")

        let channelSets                    = [channelSet1, channelSet2, channelSet3]
        let expectedUniqueUnallocatedCount = channelSets.reduce(0, combine: sumUnallocated)
        let total                          = channelSets.reduce(0, combine: {$0 + $1.count})

        XCTAssertEqual(RMQChannelLimit + expectedUniqueUnallocatedCount, total)
    }

    func testChannelsAreReleasedWithThreadSafety() {
        let allocator   = RMQMultipleChannelAllocator(channelSyncTimeout: 2)
        let group       = dispatch_group_create()
        let queues      = [
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
        ]
        allocateAll(allocator)

        dispatch_group_async(group, queues[0]) {
            for n in 1...RMQChannelLimit {
                allocator.releaseChannelNumber(n)
            }
        }

        dispatch_group_async(group, queues[1]) {
            for n in 1...RMQChannelLimit {
                allocator.releaseChannelNumber(n)
            }
        }

        dispatch_group_async(group, queues[2]) {
            for n in 1...RMQChannelLimit {
                allocator.releaseChannelNumber(n)
            }
        }

        XCTAssertEqual(0, dispatch_group_wait(group, TestHelper.dispatchTimeFromNow(10)), "Timed out waiting for releases")
        XCTAssertEqual(1, allocator.allocate().channelNumber)
    }

    func sumUnallocated(accumulator: Int, current: Set<NSNumber>) -> Int {
        return accumulator + (current.count == self.allocationsPerQueue ? 0 : 1)
    }

}
