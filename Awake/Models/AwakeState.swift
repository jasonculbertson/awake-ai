import Foundation

struct ActivationReason: Identifiable, Equatable {
    let id: UUID
    let ruleID: UUID
    let description: String
    let icon: String // SF Symbol name

    init(id: UUID = UUID(), ruleID: UUID = UUID(), description: String, icon: String = "sun.max.fill") {
        self.id = id
        self.ruleID = ruleID
        self.description = description
        self.icon = icon
    }
}

enum AwakeState: Equatable {
    case inactive
    case active(reasons: [ActivationReason])

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var reasons: [ActivationReason] {
        if case .active(let reasons) = self { return reasons }
        return []
    }
}
