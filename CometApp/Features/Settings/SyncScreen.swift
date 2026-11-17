//
//  SyncScreen.swift
//  Comet
//
//  Sync is the next release, not a switch that lies. This screen shows what is
//  already true — every change is journalled with a device stamp and a content
//  digest, and identity is the relative path — and what will happen when a
//  transport is attached.
//

import SwiftUI

struct SyncScreen: View {
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var confirmCompact = false

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(eyebrow: "Next release",
                                 title: "Sync",
                                 subtitle: "One workspace, several devices",
                                 close: close)

                    hero
                    deviceCard
                    readyCard
                    plannedCard
                    journalCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog("Compact the change journal?",
                            isPresented: $confirmCompact, titleVisibility: .visible) {
            Button("Compact", role: .destructive) {
                // Keeping nothing is only safe because nothing consumes the
                // journal yet; this is the honest version of "clear".
                model.compactJournal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The facts recorded so far are dropped. Nothing in your workspace changes.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coming in a later update")
                        .font(type.title(17))
                        .foregroundStyle(theme.ink)
                    Text("You are running the foundation today.")
                        .font(type.prose(12.5))
                        .foregroundStyle(theme.tertiary)
                }
                Spacer(minLength: 0)
            }
            Text("Your files already travel however you move the folder — iCloud Drive, a USB stick, a git repository. What sync will add is the part that lives beside the files: tags, pins, favourites, the calendar, feeds and their read state.")
                .font(type.prose(12.5))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: .constant(model.settings.syncEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync across devices")
                        .font(type.prose(13.5))
                        .foregroundStyle(theme.ink)
                    Text("The switch will do something when the transport ships.")
                        .font(type.prose(10.5))
                        .foregroundStyle(theme.tertiary)
                }
            }
            .tint(theme.accent)
            .disabled(true)
            .opacity(0.65)
        }
        .padding(16)
        .cometCard(radius: 24, lift: 0.5)
    }

    private var deviceCard: some View {
        card("This device") {
            row("Name", model.sync.deviceName)
            row("Device ID", String(model.sync.deviceID.prefix(8)).uppercased())
            row("Workspace", model.workspaceName)
            row("Profile updated", CometDate.relative(model.sync.profileUpdated))
        }
    }

    private var readyCard: some View {
        card("What is already in place") {
            bullet("Change journal", "\(model.sync.pendingChanges) facts recorded")
            bullet("Identity", "relative paths — no absolute paths, no device paths")
            bullet("Digests", "every edit carries a content fingerprint")
            bullet("Deletes", "recorded as facts, not inferred from absence")
            bullet("Rebuild", "the profile is one versioned JSON document")
        }
    }

    private var plannedCard: some View {
        card("What the update will do") {
            bullet("Transport", "a folder in iCloud Drive, or a server you choose")
            bullet("Conflicts", "the newer edit wins; the other becomes a copy beside it, never overwritten")
            bullet("Vault", "excluded unless you turn it on — a leaked backup should not be a leaked vault")
            bullet("Offline", "changes queue locally and settle when the device is back")
        }
    }

    private var journalCard: some View {
        card("Change journal") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.sync.pendingChanges)")
                        .font(type.display(28))
                        .foregroundStyle(theme.ink)
                    Text(model.sync.lastRun == nil ? "never synced" : "last run " + CometDate.relative(model.sync.lastRun ?? Date()))
                        .font(type.mono(10.5))
                        .foregroundStyle(theme.tertiary)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    confirmCompact = true
                } label: {
                    Text("Compact")
                        .font(type.label(12.5, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(Capsule().fill(theme.raised))
                }
                .buttonStyle(PressableStyle())
                .disabled(model.sync.pendingChanges == 0)
            }
            Text("Facts are written beside the workspace's profile, in the app's storage. They are small and bounded to 4,000 entries.")
                .font(type.prose(11))
                .foregroundStyle(theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: title)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cometCard(radius: 24, lift: 0.5)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(type.prose(12.5))
                .foregroundStyle(theme.tertiary)
            Spacer()
            Text(value)
                .font(type.mono(11.5))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
    }

    private func bullet(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(theme.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(type.label(12.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(detail)
                    .font(type.prose(11))
                    .foregroundStyle(theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
