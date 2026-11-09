import AVFoundation
import SwiftUI
import Vision
import VisionKit
import HumbleCore

/// Reads the sign-in QR code of the web profile: only a Humble Planning sign-in link is accepted;
/// other codes are ignored. (The Camera app of iOS opens these links too.)
struct ScannerView: View {
    let onLink: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch permission {
            case .authorized:
                if DataScannerViewController.isSupported {
                    QRScanner(onLink: onLink).ignoresSafeArea()
                } else {
                    message(String(localized: .scanPermission), systemImage: "camera.metering.unknown")
                }
            case .denied, .restricted:
                VStack(spacing: 20) {
                    message(String(localized: .scanPermission), systemImage: "video.slash")
                    Button(String(localized: .scanAllow)) {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    .buttonStyle(.glassProminent)
                }
            default:
                Color.clear
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.backward").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: .back))
                    Spacer()
                }
                Spacer()
                Text(.scanHint)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 32)
            }
            .padding(16)
        }
        .task {
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 48))
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onLink: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLink: onLink) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onLink: (URL) -> Void
        private var done = false

        init(onLink: @escaping (URL) -> Void) { self.onLink = onLink }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                guard !done, case .barcode(let code) = item, let text = code.payloadStringValue,
                      QRLogin(link: text) != nil, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                done = true
                scanner.stopScanning()
                onLink(url)
            }
        }
    }
}
