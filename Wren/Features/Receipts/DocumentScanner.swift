import SwiftUI
import VisionKit

/// VisionKit's document camera: edge detection, perspective correction and
/// multi-page capture, all for free. Writing a camera UI by hand would be worse
/// in every respect, and this needs no entitlement — which matters on free-tier
/// signing.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    /// False on a device with no camera; the caller shows an explanation rather
    /// than presenting an empty scanner.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            Logger.shared.info("receipts", "scanned \(pages.count) page(s)")
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            Logger.shared.debug("receipts", "scan cancelled")
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            Logger.shared.error("receipts", "scan failed: \(error.localizedDescription)")
            onCancel()
        }
    }
}
