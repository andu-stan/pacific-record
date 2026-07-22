import SwiftUI
import VisionKit
import Vision
import AVFoundation

/// Live barcode scanning via VisionKit's `DataScannerViewController`. Recognizes
/// UPC/EAN symbologies and reports the first payload string. Availability is
/// checked by the caller (`DataScannerViewController.isSupported`); the Simulator
/// has no camera and falls back to manual entry.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var isTorchOn: Bool = false
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
        // Only touch the capture device when the torch state actually changes —
        // poking AVCaptureDevice on every update fights the scanner's own session.
        if context.coordinator.torchOn != isTorchOn {
            context.coordinator.torchOn = isTorchOn
            setTorch(on: isTorchOn)
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    private func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Best effort — the scanner owns the session; ignore torch failures.
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        var torchOn = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        // Reports each recognized barcode; the model gates re-entrancy so a
        // barcode still in frame doesn't trigger repeated lookups.
        private func handle(_ items: [RecognizedItem]) {
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
