import SwiftUI
import UIKit

/// The standard iOS share sheet (`UIActivityViewController`), for sharing an
/// exported library file to Files, AirDrop, Mail, and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
