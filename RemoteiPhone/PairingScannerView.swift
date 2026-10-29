import AVFoundation
import SwiftUI
import VisionKit

/// Scans the QR code the Mac shows. `onCode` returns true once it accepted a valid pairing code.
struct PairingScannerView: View {
    let onCode: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?
    @State private var rejected = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan Mac's code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { cameraAllowed = await AVCaptureDevice.requestAccess(for: .video) }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if !DataScannerViewController.isSupported {
            message("Scanning isn't available on this device.\nScan the code with the Camera app instead: it opens CouchRemote.")
        } else if cameraAllowed == false {
            VStack(spacing: 14) {
                message("Camera access is off.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if cameraAllowed == true {
            ZStack(alignment: .bottom) {
                ScannerRepresentable { code in
                    if !onCode(code) { rejected = true }
                }
                .ignoresSafeArea()
                Text(rejected ? "That isn't a CouchRemote code." : "On your Mac: menu bar › Pair New iPhone…")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.bottom, 32)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.7))
            .padding(32)
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue { onCode(payload) }
            }
        }
    }
}
