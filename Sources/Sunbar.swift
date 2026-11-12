// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

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

            VStack(spacing: 6) {
                HStack {
                    Text("Boost")
                    Spacer()
                    Text(boost.strength.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $boost.strength, in: 0.05...1) {
                    Text("Boost")
                }
                .labelsHidden()
                .controlSize(.regular)
                .frame(height: 24)
                .accessibilityValue(boost.strength.formatted(.percent.precision(.fractionLength(0))))
            }
            .disabled(!boost.enabled)

            Divider()

            Button("About Sunbar") {
                NSApp.orderFrontStandardAboutPanel()
                NSApp.activate()
            }
            Button("Source on GitHub") {
                NSWorkspace.shared.open(URL(string: "https://github.com/othmanehousni/Sunbar")!)
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

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
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
