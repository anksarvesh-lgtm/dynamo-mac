import SwiftUI

extension View {
    func dataAnnotationID(_ id: String) -> some View {
        accessibilityIdentifier("data-annotation-id=\(id)")
    }
}

