import Foundation

public struct RingBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element]
    private var head: Int = 0
    private var count: Int = 0
    public let capacity: Int

    public init(capacity: Int, defaultValue: Element) {
        self.capacity = max(capacity, 1)
        self.storage = Array(repeating: defaultValue, count: self.capacity)
    }

    public mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    public var elements: [Element] {
        guard count > 0 else { return [] }
        if count < capacity {
            return Array(storage.prefix(count))
        }
        let tail = Array(storage[head..<capacity])
        let front = Array(storage[0..<head])
        return tail + front
    }

    public var latest: Element? {
        guard count > 0 else { return nil }
        let index = (head - 1 + capacity) % capacity
        return storage[index]
    }
}

public struct MetricSample: Sendable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date = Date(), value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}
