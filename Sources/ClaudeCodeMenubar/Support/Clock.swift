import Foundation

protocol ClockProtocol: Sendable {
    func now() -> Date
}

struct SystemClock: ClockProtocol {
    func now() -> Date { Date() }
}
