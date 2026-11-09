import SwiftUI
import HumbleCore

/// The account's own details: name, phones, job, colour. The e-mail address only changes through
/// an administrator.
struct ProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var firstName = ""
    @State private var phone = ""
    @State private var mobile = ""
    @State private var job = ""
    @State private var color: String?
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?

    static let colors = ["#5A17FF", "#2563EB", "#0891B2", "#059669", "#65A30D", "#D97706",
                         "#EA580C", "#DC2626", "#DB2777", "#7C3AED", "#475569", "#18181B"]

    var body: some View {
        NavigationStack {
            Form {
                if saved { Banner(text: String(localized: .profileSaved), systemImage: "checkmark.circle") }
                if let error { Banner(text: error, tone: .error) }
                Section {
                    TextField(String(localized: .profileName) + " *", text: limited($name, 100))
                        .textContentType(.familyName)
                    TextField(String(localized: .profileFirstName), text: limited($firstName, 100))
                        .textContentType(.givenName)
                    LabeledContent(String(localized: .profileEmail), value: app.repository.references.user.email ?? "")
                } footer: {
                    Text(.profileEmailHelp)
                }
                Section {
                    TextField(String(localized: .profilePhone), text: limited($phone, 20))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField(String(localized: .profileMobile), text: limited($mobile, 20))
                        .keyboardType(.phonePad)
                    TextField(String(localized: .profileJob), text: limited($job, 100))
                        .textContentType(.jobTitle)
                }
                Section(String(localized: .profileColor)) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 4) {
                        ForEach(Self.colors, id: \.self) { swatch($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(String(localized: .profileTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(String(localized: .save), role: .confirm, action: save)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .onAppear(perform: fill)
    }

    private func swatch(_ hex: String) -> some View {
        let selected = color?.caseInsensitiveCompare(hex) == .orderedSame
        return Button {
            color = hex
            saved = false
        } label: {
            ZStack {
                Circle().fill(Color(serverHex: hex) ?? .gray)
                    .overlay(Circle().strokeBorder(.primary.opacity(selected ? 1 : 0.12), lineWidth: selected ? 2 : 1))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(contentIsDark(hex) ? Palette.darkText : .white)
                }
            }
            .frame(width: 34, height: 34)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: .profileColorItem(hex)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func limited(_ binding: Binding<String>, _ maximum: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: {
            binding.wrappedValue = String($0.prefix(maximum))
            saved = false
        })
    }

    private func fill() {
        let user = app.repository.references.user
        name = user.name
        firstName = user.firstName ?? ""
        phone = user.phone ?? ""
        mobile = user.mobile ?? ""
        job = user.job ?? ""
        color = user.color
    }

    private func save() {
        saving = true
        error = nil
        Task {
            do {
                try await app.repository.updateProfile(UpdateProfileRequest(name: name, firstName: firstName, phone: phone,
                                                                            mobile: mobile, job: job, color: color))
                try? await app.repository.loadReferences()
                saved = true
            } catch {
                self.error = screenMessage(error)
            }
            saving = false
        }
    }
}

/// A new password; this session stays signed in.
struct PasswordSheet: View {
    let onChanged: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var error: String?

    private var mismatch: Bool { !confirmation.isEmpty && new != confirmation }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Banner(text: error, tone: .error) }
                SecureField(String(localized: .passwordCurrent), text: $current).textContentType(.password)
                SecureField(String(localized: .passwordNew), text: $new).textContentType(.newPassword)
                Section {
                    SecureField(String(localized: .passwordConfirm), text: $confirmation).textContentType(.newPassword)
                } footer: {
                    if mismatch { Text(.passwordMismatch).foregroundStyle(Palette.danger) }
                }
            }
            .navigationTitle(String(localized: .passwordChange))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(String(localized: .save), role: .confirm, action: save).disabled(current.isEmpty || new.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard new == confirmation else {
            error = String(localized: .passwordMismatch)
            return
        }
        saving = true
        error = nil
        Task {
            do {
                try await app.repository.changePassword(current: current, new: new)
                onChanged()
                dismiss()
            } catch {
                self.error = screenMessage(error)
            }
            saving = false
        }
    }
}

/// Turning the second factor off, with the password.
struct DisableTwoFactorSheet: View {
    let onDisabled: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Banner(text: error, tone: .error) }
                Section {
                    SecureField(String(localized: .loginPassword), text: $password).textContentType(.password)
                } footer: {
                    Text(.twoFactorDisableText)
                }
                Section {
                    Button(role: .destructive, action: disable) {
                        HStack {
                            Text(.twoFactorDisable)
                            if saving { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(password.isEmpty || saving)
                }
            }
            .navigationTitle(String(localized: .twoFactorDisable))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func disable() {
        saving = true
        error = nil
        Task {
            do {
                try await app.repository.disableTwoFactor(password: password)
                onDisabled()
                dismiss()
            } catch {
                self.error = screenMessage(error)
            }
            saving = false
        }
    }
}

/// Turning the second factor on from the settings.
struct TwoFactorSetupSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                TwoFactorSetupFlow(finishing: finishing) {
                    finishing = true
                    Task {
                        try? await app.repository.loadReferences()
                        dismiss()
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: .twoFactorEnable))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        }
    }
}
