import Foundation
import SwiftUI

public extension View {
    /// Applies the given transform if the given optional is unwrapped.
    /// - Parameters:
    ///   - value: The optional to unwrap.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the optional is not nil
    @ViewBuilder func whenSet<T, Value>(_ optional: Value?, transform: (Self, Value) -> T) -> some View where T: View {
        if let optional {
            transform(self, optional)
        } else {
            self
        }
    }

    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
