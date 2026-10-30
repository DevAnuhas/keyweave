import SwiftUI

/// At-a-glance setup dashboard (like Cotypist's Setup screen): permission grants,
/// model download state, and the couple of toggles that matter for first use —
/// each with a live status and a one-click action. Reuses the same signals as the
/// first-run onboarding window, but stays available in Settings forever.
struct SetupPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var models: LlamaModelManager

    @State private var trusted = AccessibilityBridge.isTrusted()
    @State private var screenOK = ScreenContextProvider.shared.hasPermission()
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var modelReady: Bool { models.isLoaded }
    private var allSet: Bool { trusted && modelReady && settings.isEnabled && settings.inputMonitoringState == .active }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: allSet ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.title2)
                        .foregroundStyle(allSet ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(allSet ? "All set!" : "Finish setup").font(.headline)
                        Text(allSet ? "KeyWeaver is ready to use. Start typing in a supported text field and press Tab to accept a suggestion." : "Complete the steps below to start getting suggestions.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                statusRow(
                    ok: !AppSafetyPolicy.inputMonitoringEnabled || trusted, title: "Accessibility permission",
                    detail: AppSafetyPolicy.inputMonitoringEnabled ? "Required — lets KeyWeaver read the field you're typing in and insert completions." : "Required to start suggestions.",
                    action: (!AppSafetyPolicy.inputMonitoringEnabled || trusted ? nil : ("Grant", { _ = AccessibilityBridge.requestTrust() })),
                    doneLabel: AppSafetyPolicy.inputMonitoringEnabled ? "Granted" : "Not needed")

                statusRow(
                    ok: settings.inputMonitoringState == .active, title: "Keyboard monitoring",
                    detail: settings.inputMonitoringState == .failed
                        ? "Could not start. Check System Settings → Privacy & Security → Input Monitoring. KeyWeaver retries automatically."
                        : "Starts after Accessibility is granted. Suggestions can be paused from the menu bar.",
                    action: nil,
                    doneLabel: settings.inputMonitoringState == .active ? "Running" : "Not running")

                statusRow(
                    ok: screenOK, title: "Screen Recording permission",
                    detail: "Screen context and appearance capture are off in this build.",
                    action: nil,
                    doneLabel: "Off")

                modelRow

                Text("Manage macOS text suggestions in System Settings. KeyWeaver does not change that preference.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Optional") {
                Toggle("Use clipboard as context", isOn: $settings.useClipboardContext)
                    .disabled(!AppSafetyPolicy.clipboardContextEnabled)
                Text("When on, KeyWeaver reads your clipboard to better understand what you're working on. Processed locally; never stored or sent anywhere. (Free — no upgrade required.)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(poll) { _ in
            trusted = AccessibilityBridge.isTrusted()
            screenOK = ScreenContextProvider.shared.hasPermission()
        }
    }

    // MARK: - Rows

    @ViewBuilder private var modelRow: some View {
        let (ok, statusText, buttonTitle): (Bool, String, String?) = {
            switch models.status {
            case .ready: return (true, "Ready", nil)
            case .downloading(_, let f): return (false, "Downloading \(Int(f * 100))%", nil)
            case .loading: return (false, "Loading…", nil)
            case .failed: return (false, "Failed", "Retry")
            case .noModel: return (false, "Not downloaded", "Download")
            }
        }()
        LabeledContent {
            if let buttonTitle {
                Button(buttonTitle) { models.select(models.selectedID) }
            } else {
                statusPill(statusText, ok: ok)
            }
        } label: {
            rowLabel(ok: ok, title: "AI model",
                     detail: "The local model that powers completions (downloads once, then runs on-device).")
        }
    }

    @ViewBuilder
    private func statusRow(ok: Bool, title: String, detail: String,
                           action: (String, () -> Void)?, doneLabel: String) -> some View {
        LabeledContent {
            if let (label, run) = action {
                Button(label, action: run)
            } else {
                statusPill(doneLabel, ok: ok)
            }
        } label: {
            rowLabel(ok: ok, title: title, detail: detail)
        }
    }

    @ViewBuilder
    private func rowLabel(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusPill(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(ok ? .green : .secondary)
    }
}
