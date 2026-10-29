import SwiftUI

struct OnboardingView: View {
    let onGrant: () -> Void
    let onGrantScreen: () -> Void
    let onDone: () -> Void

    @State private var trusted = AccessibilityBridge.isTrusted()
    @State private var screenOK = ScreenContextProvider.shared.hasPermission()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.cursor")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 4)

            Text("Welcome to Keyweave").font(.title).bold()

            Text("Free, on-device autocomplete for macOS. As you type, Keyweave suggests your next words — press Tab to accept. Nothing leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider().padding(.horizontal)

            permissionRow(
                ok: trusted,
                title: "Accessibility (required)",
                detail: "Lets Keyweave read the field you're typing in and insert accepted suggestions.",
                buttonTitle: "Grant Accessibility",
                action: onGrant)

            Text("Screen context, writing memory and sync are off in this build.")
                .font(.callout).foregroundStyle(.secondary)

            Button("Get Started") { onDone() }
                .keyboardShortcut(.defaultAction)
                .disabled(!trusted)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(width: 460)
        .padding()
        .onReceive(poll) { _ in
            trusted = AccessibilityBridge.isTrusted()
            screenOK = ScreenContextProvider.shared.hasPermission()
        }
    }

    @ViewBuilder
    private func permissionRow(ok: Bool, title: String, detail: String,
                               buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !ok {
                    Button(buttonTitle, action: action).padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
