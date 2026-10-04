import SwiftUI

enum SessionColors {
    static let workingTint = Color.Resolved(red: 0.4, green: 0.65, blue: 1)
    static let attentionTint = Color.Resolved(red: 1, green: 0.62, blue: 0.04)
    static let finishedTint = Color.Resolved(red: 0.2, green: 0.78, blue: 0.35)
    static let idleTint = Color.Resolved(red: 0.56, green: 0.56, blue: 0.58)
    static let failedTint = Color.Resolved(red: 1, green: 0.27, blue: 0.23)
    static let working = Color(workingTint)
}
