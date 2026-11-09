import CoreImage.CIFilterBuiltins
import SwiftUI
import HumbleCore

/// Turning the second factor on: password, then the code of the authenticator app, then the backup
/// codes. Used at a sign-in that requires it and from the settings.
struct TwoFactorSetupFlow: View {
    var finishing = false
    let onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @State private var stage = Stage.password
    @State private var password = ""
    @State private var code = ""
    @State private var setup: TwoFactorSetup?
    @State private var backupCodes: [String] = []
    @State private var loading = false
    @State private var error: String?

    enum Stage { case password, code, backupCodes }

    var body: some View {
        VStack(spacing: 14) {
            if let error { Banner(text: error, tone: .error) }
            switch stage {
            case .password:
                Text(.twoFactorSetupPassword)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SecureField(String(localized: .loginPassword), text: $password)
                    .textContentType(.password)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .onSubmit(enable)
                ProgressButton(title: String(localized: .continueAction), loading: loading, enabled: !password.isEmpty, action: enable)
            case .code:
                Text(.twoFactorSetupScan)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let setup {
                    QRCodeImage(text: setup.totpURI)
                        .frame(width: 220, height: 220)
                        .accessibilityLabel(String(localized: .twoFactorSetupQr))
                    if let url = URL(string: setup.totpURI) {
                        Link(destination: url) { Label(String(localized: .twoFactorSetupOpenApp), systemImage: "key") }
                    }
                    Text(.twoFactorSetupSecret)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(setup.secret)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("twoFactorSetup.secret")
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                }
                TextField(String(localized: .twoFactorCode), text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title3.monospacedDigit())
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                    .onChange(of: code) { code = String(code.filter(\.isNumber).prefix(6)) }
                ProgressButton(title: String(localized: .twoFactorVerify), loading: loading, enabled: code.count == 6, action: verify)
            case .backupCodes:
                Banner(text: String(localized: .twoFactorBackupKeep), tone: .warning)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(backupCodes, id: \.self) { Text($0).font(.body.monospaced()) }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                ProgressButton(title: String(localized: .twoFactorBackupDone), loading: finishing, action: onFinished)
            }
        }
    }

    private func enable() {
        guard !password.isEmpty, !loading else { return }
        run {
            setup = try await app.repository.enableTwoFactor(password: password)
            password = ""
            stage = .code
        }
    }

    private func verify() {
        guard code.count == 6, !loading else { return }
        run {
            backupCodes = try await app.repository.verifyTwoFactor(code: code)
            stage = .backupCodes
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        loading = true
        error = nil
        Task {
            do { try await action() } catch { self.error = screenMessage(error) }
            loading = false
        }
    }
}

/// A QR code, always black on white.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(8)
                .background(.white, in: .rect(cornerRadius: 12))
        }
    }

    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
