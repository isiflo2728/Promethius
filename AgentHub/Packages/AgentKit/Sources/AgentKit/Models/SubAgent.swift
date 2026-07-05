import Foundation
import SwiftData

/// A specialized worker that a parent `Agent` can delegate a step to.
@Model
public final class SubAgent {
    public var id: UUID = UUID()
    public var name: String = ""
    public var role: String = ""
    public var systemPrompt: String = ""
    public var orderIndex: Int = 0

    public var parent: Agent?

    public init(name: String, role: String = "", systemPrompt: String = "", orderIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.role = role
        self.systemPrompt = systemPrompt
        self.orderIndex = orderIndex
    }
}
