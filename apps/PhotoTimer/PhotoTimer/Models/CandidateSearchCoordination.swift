import Foundation

/// 候補1件を消費する前後の全経路で共通利用する探索予算。
struct CandidateSearchBudget {
    let maximumCount: Int
    let maximumSeconds: TimeInterval
    private(set) var consumedCount = 0

    mutating func beginCandidate(elapsedSeconds: TimeInterval) -> Bool {
        guard consumedCount < maximumCount, elapsedSeconds < maximumSeconds else { return false }
        consumedCount += 1
        return true
    }

    func isExhausted(elapsedSeconds: TimeInterval) -> Bool {
        consumedCount >= maximumCount || elapsedSeconds >= maximumSeconds
    }
}

/// 世代が一致するTaskだけが追加でき、上限を超えない先読みキュー。
struct GenerationBoundedQueue<Element> {
    let limit: Int
    private(set) var generation: UInt64 = 0
    private(set) var elements: [Element] = []

    mutating func advanceGeneration(clear: Bool) -> UInt64 {
        generation &+= 1
        if clear { elements.removeAll() }
        return generation
    }

    func isCurrent(_ candidate: UInt64) -> Bool { candidate == generation }

    @discardableResult
    mutating func append(_ element: Element, generation candidate: UInt64) -> Bool {
        guard isCurrent(candidate), elements.count < limit else { return false }
        elements.append(element)
        return true
    }

    mutating func popFirst() -> Element? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }
}
