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
            if let icon = BrandAssets.appIcon() {
                Image(nsImage: icon)
                    .resizable().interpolation(.high)
                    .frame(width: 72, height: 72)
                    .padding(.top, 4)
            }

            Text("Welcome to KeyWeaver").font(.title).bold()

            Text("An early preview of on-device autocomplete for macOS. Suggestions and input monitoring are disabled in this preview.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Divider().padding(.horizontal)

            permissionRow(
                ok: trusted,
                title: AppSafetyPolicy.inputMonitoringEnabled ? "Accessibility (required)" : "Accessibility",
                detail: AppSafetyPolicy.inputMonitoringEnabled ? "Lets KeyWeaver read the field you're typing in and insert accepted suggestions." : "Not needed while suggestions are disabled in this preview.",
                buttonTitle: "Grant Accessibility",
                action: onGrant)

            Text("Screen context, writing memory and sync are also off. You do not need to grant permissions to inspect this preview.")
                .font(.callout).foregroundStyle(.secondary)

            Button("Get Started") { onDone() }
                .keyboardShortcut(.defaultAction)
                .disabled(AppSafetyPolicy.inputMonitoringEnabled && !trusted)
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
                if !ok && AppSafetyPolicy.inputMonitoringEnabled {
                    Button(buttonTitle, action: action).padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
