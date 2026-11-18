import Testing
@testable import Agents

@Suite("Composer List Keyboard Navigation")
struct ComposerRebuildTests {

    @Test("Empty list has no next index")
    func emptyListHasNoIndex() {
        #expect(ComposerListNavigator.movedIndex(from: nil, count: 0, delta: 1) == nil)
        #expect(ComposerListNavigator.movedIndex(from: 0, count: 0, delta: -1) == nil)
    }

    @Test("No current selection starts at the near edge")
    func noCurrentStartsAtNearEdge() {
        #expect(ComposerListNavigator.movedIndex(from: nil, count: 3, delta: 1) == 0)
        #expect(ComposerListNavigator.movedIndex(from: nil, count: 3, delta: -1) == 2)
    }

    @Test("Movement wraps at both ends")
    func movementWrapsAtBothEnds() {
        #expect(ComposerListNavigator.movedIndex(from: 2, count: 3, delta: 1) == 0)
        #expect(ComposerListNavigator.movedIndex(from: 0, count: 3, delta: -1) == 2)
    }

    @Test("Movement steps within the list")
    func movementStepsWithinList() {
        #expect(ComposerListNavigator.movedIndex(from: 0, count: 3, delta: 1) == 1)
        #expect(ComposerListNavigator.movedIndex(from: 2, count: 3, delta: -1) == 1)
        #expect(ComposerListNavigator.movedIndex(from: 1, count: 5, delta: 1) == 2)
    }

    @Test("Single-item list stays on its only index")
    func singleItemListStays() {
        #expect(ComposerListNavigator.movedIndex(from: 0, count: 1, delta: 1) == 0)
        #expect(ComposerListNavigator.movedIndex(from: 0, count: 1, delta: -1) == 0)
        #expect(ComposerListNavigator.movedIndex(from: nil, count: 1, delta: 1) == 0)
    }
}
