import ServiceManagement
import SwiftUI

@main
struct Sunbar: App {
    @NSApplicationDelegateAdaptor(BoostController.self) private var boost

    var body: some Scene {
        MenuBarExtra("Sunbar", systemImage: boost.enabled ? "sun.max.fill" : "sun.max") {
            BoostMenu(boost: boost)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct BoostMenu: View {
    @ObservedObject var boost: BoostController
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private var startsAtLogin: Bool {
        loginStatus == .enabled || loginStatus == .requiresApproval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text("Sunbar").font(.title3.weight(.semibold))
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("XDR Brightness", isOn: $boost.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            Text(boost.status)
                .font(.callout)
                .foregroundStyle(.secondary)

            Slider(value: $boost.strength, in: 0.05...1, step: 0.01) {
                Text("Boost")
            }
            .accessibilityValue(boost.strength.formatted(.percent.precision(.fractionLength(0))))
            .disabled(!boost.enabled)

            Picker("Boost method", selection: $boost.method) {
                ForEach(BoostMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            if boost.method == .direct {
                Text("Uses the stock SDR preset while the boost is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("About Sunbar") {
                NSApp.orderFrontStandardAboutPanel()
                NSApp.activate()
            }

            Button(startsAtLogin ? "Stop Opening at Login" : "Open at Login") {
                setLoginItem(!startsAtLogin)
            }
            if loginStatus == .requiresApproval {
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError {
                Text(loginError).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(boost.diagnostics, forType: .string)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 310)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}
