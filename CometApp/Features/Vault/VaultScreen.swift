//
//  VaultScreen.swift
//  Comet
//
//  Passwords, sealed on the device with the same envelope Comet's desktop app
//  writes. Three states, and the screen is honest about which one it is in: no
//  vault yet, locked, or open.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VaultScreen: View {
    let close: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var password = ""
    @State private var confirmation = ""
    @State private var withRecovery = true
    @State private var busy = false
    @State private var recoveryBox: RecoveryCodeBox?
    @State private var editing: PasswordEntry?
    @State private var reading: PasswordEntry?
    @State private var showingRecoveryUnlock = false
    @State private var recoveryInput = ""
    @State private var showingImport = false
    @State private var search = ""

    private var vault: VaultStore { model.vault }

    private var entries: [PasswordEntry] {
        guard !search.isEmpty else { return vault.entries }
        let needle = search.lowercased()
        return vault.entries.filter {
            $0.name.lowercased().contains(needle)
            || $0.username.lowercased().contains(needle)
            || $0.website.lowercased().contains(needle)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(eyebrow: "Encrypted",
                                 title: "Passwords",
                                 subtitle: subtitle,
                                 close: close) {
                        trailing
                    }

                    switch vault.state {
                    case .empty:
                        createForm
                    case .locked:
                        unlockForm
                    case .unlocked:
                        unlockedList
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $recoveryBox) { box in
            recoverySheet(box.code)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.height(380)])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .sheet(item: $editing) { entry in
            VaultEntrySheet(entry: entry)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.large])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .sheet(item: $reading) { entry in
            VaultDetailSheet(entry: entry) {
                editing = entry
                reading = nil
            }
            .environmentObject(model)
            .environment(\.comet, theme)
            .environment(\.type, type)
            .presentationDetents([.medium, .large])
            .presentationBackground(.clear)
            .presentationCornerRadius(34)
        }
        .sheet(isPresented: $showingRecoveryUnlock) {
            recoveryUnlockSheet
                .presentationDetents([.height(320)])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    try vault.importBackup(data: data)
                    model.toast.show("Backup imported", tone: .success)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var subtitle: String {
        switch vault.state {
        case .empty: return "No vault yet"
        case .locked: return "Locked · AES-256-GCM"
        case .unlocked: return "\(vault.entries.count) entries · unlocked"
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if vault.state == .unlocked {
            HStack(spacing: 8) {
                Menu {
                    if let url = vault.exportFile() {
                        ShareLink(item: url) {
                            Label("Export encrypted backup", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import a backup", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Button {
                        Haptics.tap()
                        vault.lock()
                        password = ""
                    } label: {
                        Label("Lock the vault", systemImage: "lock")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 38, height: 38)
                        .glassPanel(radius: 19)
                }
                Button {
                    Haptics.press()
                    editing = PasswordEntry()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(theme.accentGradient))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Empty

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Glyph(symbol: "lock.shield", size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Make a vault")
                            .font(type.title(17))
                            .foregroundStyle(theme.ink)
                        Text("One master password. Nothing leaves this device.")
                            .font(type.prose(12))
                            .foregroundStyle(theme.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                SecureField("Master password", text: $password)
                    .font(type.prose(15))
                    .foregroundStyle(theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
                SecureField("Again", text: $confirmation)
                    .font(type.prose(15))
                    .foregroundStyle(theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
                Toggle("Also make a recovery code", isOn: $withRecovery)
                    .font(type.prose(13))
                    .tint(theme.accent)
                PrimaryAction(title: busy ? "Sealing…" : "Create vault", icon: "lock.fill") {
                    create()
                }
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)

            Text("The vault is encrypted with AES-256-GCM using a key derived from your master password (PBKDF2-SHA256, 600,000 iterations). Comet stores the sealed envelope, never the password. A `comet-passwords` backup from the desktop app opens here too.")
                .font(type.prose(11.5))
                .foregroundStyle(theme.tertiary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
    }

    private func create() {
        guard password == confirmation else {
            model.errorMessage = "The two passwords don't match."
            return
        }
        busy = true
        let value = password
        let recovery = withRecovery
        Task {
            do {
                let code = try await vault.createVault(masterPassword: value, withRecovery: recovery)
                password = ""
                confirmation = ""
                if let code { recoveryBox = RecoveryCodeBox(code: code) }
                Haptics.success()
            } catch {
                model.errorMessage = error.localizedDescription
                Haptics.error()
            }
            busy = false
        }
    }

    // MARK: Locked

    private var unlockForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Glyph(symbol: "lock.fill", size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Locked")
                            .font(type.title(17))
                            .foregroundStyle(theme.ink)
                        Text("Unlock to read or add entries.")
                            .font(type.prose(12))
                            .foregroundStyle(theme.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                SecureField("Master password", text: $password)
                    .font(type.prose(15))
                    .foregroundStyle(theme.ink)
                    .submitLabel(.go)
                    .onSubmit(unlock)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
                PrimaryAction(title: busy ? "Opening…" : "Unlock", icon: "lock.open") {
                    unlock()
                }
                .disabled(busy)
                if vault.hasRecovery {
                    Button {
                        Haptics.tap()
                        showingRecoveryUnlock = true
                    } label: {
                        Text("Use a recovery code")
                            .font(type.label(12.5, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(16)
            .cometCard(radius: 24, lift: 0.5)
        }
        .padding(.horizontal, 20)
    }

    private func unlock() {
        guard !busy, !password.isEmpty else { return }
        busy = true
        let value = password
        Task {
            do {
                try await vault.unlock(masterPassword: value)
                password = ""
                Haptics.success()
            } catch {
                model.errorMessage = error.localizedDescription
                Haptics.error()
            }
            busy = false
        }
    }

    // MARK: Unlocked

    private var unlockedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.tertiary)
                TextField("Search the vault", text: $search)
                    .font(type.prose(14))
                    .foregroundStyle(theme.ink)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))

            if entries.isEmpty {
                EmptyState(icon: "key",
                           title: search.isEmpty ? "No entries yet" : "Nothing matches",
                           message: search.isEmpty
                            ? "Store a login, a licence key, the wifi password — anything you'd rather not keep in a note."
                            : "Try another word.")
                if search.isEmpty {
                    PrimaryAction(title: "Add an entry", icon: "plus") {
                        editing = PasswordEntry()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            Haptics.tap()
                            reading = entry
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(theme.accent.opacity(0.14))
                                        .frame(width: 40, height: 40)
                                    Text(String(entry.name.prefix(1)).uppercased())
                                        .font(type.title(16))
                                        .foregroundStyle(theme.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(type.label(14.5, weight: .semibold))
                                        .foregroundStyle(theme.ink)
                                        .lineLimit(1)
                                    Text(entry.username.isEmpty ? (entry.website.isEmpty ? "No username" : entry.website) : entry.username)
                                        .font(type.prose(11.5))
                                        .foregroundStyle(theme.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.tertiary)
                            }
                            .padding(.vertical, 9)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = entry.password
                                model.toast.show("Password copied", tone: .success)
                            } label: {
                                Label("Copy password", systemImage: "doc.on.doc")
                            }
                            Button {
                                editing = entry
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                do {
                                    try vault.delete(entry)
                                    Haptics.warning()
                                } catch {
                                    model.errorMessage = error.localizedDescription
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if index < entries.count - 1 {
                            CometDivider().padding(.leading, 62)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .cometCard(radius: 24, lift: 0.5)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Recovery

    private func recoverySheet(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            Text("Your recovery code")
                .font(type.display(24))
                .foregroundStyle(theme.ink)
            Text("Write this down and keep it somewhere else. It is the only way back into the vault if the master password is lost, and Comet does not keep a copy.")
                .font(type.prose(12.5))
                .foregroundStyle(theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(code)
                .font(type.mono(13, weight: .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = code
                    model.toast.show("Recovery code copied", tone: .success)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(type.label(14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(theme.raised))
                }
                .buttonStyle(PressableStyle())
                Button {
                    recoveryBox = nil
                } label: {
                    Text("I saved it")
                        .font(type.label(14, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(theme.accentGradient))
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private var recoveryUnlockSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            Text("Recovery code")
                .font(type.display(24))
                .foregroundStyle(theme.ink)
            TextField("XXXX-XXXX-XXXX-…", text: $recoveryInput)
                .font(type.mono(13))
                .foregroundStyle(theme.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))
            Button {
                let code = recoveryInput
                Task {
                    do {
                        try await vault.unlockWithRecovery(code: code)
                        showingRecoveryUnlock = false
                        recoveryInput = ""
                        Haptics.success()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Text("Unlock")
                    .font(type.label(15, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Capsule().fill(theme.accentGradient))
            }
            .buttonStyle(PressableStyle())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }
}

// `.sheet(item:)` needs an Identifiable thing, and a String is not.
struct RecoveryCodeBox: Identifiable {
    let code: String
    var id: String { code }
}

// MARK: - Detail

struct VaultDetailSheet: View {
    let entry: PasswordEntry
    var onEdit: () -> Void

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack {
                Text(entry.name)
                    .font(type.display(24))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.raised))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    field("Username", entry.username) {
                        UIPasteboard.general.string = entry.username
                        model.toast.show("Username copied", tone: .success)
                    }
                    passwordField
                    if !entry.website.isEmpty {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WEBSITE")
                                    .font(type.label(9.5, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundStyle(theme.tertiary)
                                Text(entry.website)
                                    .font(type.prose(14))
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let host = entry.siteHost, let url = URL(string: "https://" + host) {
                                Button {
                                    openURL(url)
                                } label: {
                                    Image(systemName: "safari")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(theme.raised))
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
                    }
                    if !entry.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOTES")
                                .font(type.label(9.5, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(theme.tertiary)
                            Text(entry.notes)
                                .font(type.prose(13.5))
                                .foregroundStyle(theme.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
                    }

                    HStack(spacing: 10) {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                                .font(type.label(13.5, weight: .semibold))
                                .foregroundStyle(theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(theme.raised))
                        }
                        .buttonStyle(PressableStyle())
                        Button {
                            do {
                                try model.vault.delete(entry)
                                dismiss()
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(type.label(13.5, weight: .semibold))
                                .foregroundStyle(Color.red.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Capsule().fill(theme.raised))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.top, 4)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PASSWORD")
                .font(type.label(9.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.tertiary)
            HStack(spacing: 8) {
                Text(revealed ? entry.password : String(repeating: "•", count: min(18, max(6, entry.password.count))))
                    .font(type.mono(15, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    revealed.toggle()
                    Haptics.tap()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                }
                Button {
                    UIPasteboard.general.string = entry.password
                    model.toast.show("Password copied", tone: .success)
                    Haptics.success()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
    }

    private func field(_ title: String, _ value: String, copy: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(type.label(9.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.tertiary)
                Text(value.isEmpty ? "—" : value)
                    .font(type.prose(14))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
            }
            Spacer()
            if !value.isEmpty {
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
    }
}

// MARK: - Editor

struct VaultEntrySheet: View {
    let entry: PasswordEntry

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var website: String
    @State private var username: String
    @State private var password: String
    @State private var notes: String
    @State private var revealed = false
    @State private var length: Double = 20

    init(entry: PasswordEntry) {
        self.entry = entry
        _name = State(initialValue: entry.name)
        _website = State(initialValue: entry.website)
        _username = State(initialValue: entry.username)
        _password = State(initialValue: entry.password)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetGrabber()
            HStack {
                Text(entry.name.isEmpty ? "New entry" : "Edit entry")
                    .font(type.display(24))
                    .foregroundStyle(theme.ink)
                Spacer()
                Button(action: save) {
                    Text("Save")
                        .font(type.label(14, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(theme.accentGradient))
                }
                .buttonStyle(PressableStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    field("Name", text: $name, placeholder: "GitHub")
                    field("Website", text: $website, placeholder: "github.com", keyboard: .URL)
                    field("Username", text: $username, placeholder: "you@example.com")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PASSWORD")
                            .font(type.label(9.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(theme.tertiary)
                        HStack(spacing: 8) {
                            Group {
                                if revealed {
                                    TextField("Password", text: $password)
                                } else {
                                    SecureField("Password", text: $password)
                                }
                            }
                            .font(type.mono(14))
                            .foregroundStyle(theme.ink)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button {
                                revealed.toggle()
                            } label: {
                                Image(systemName: revealed ? "eye.slash" : "eye")
                                    .foregroundStyle(theme.secondary)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))

                        HStack(spacing: 8) {
                            Slider(value: $length, in: 8...48, step: 1)
                                .tint(theme.accent)
                            Text("\(Int(length))")
                                .font(type.mono(11))
                                .foregroundStyle(theme.tertiary)
                                .frame(width: 22)
                            Button {
                                password = PasswordGenerator.generate(length: Int(length))
                                revealed = true
                                Haptics.success()
                            } label: {
                                Image(systemName: "dice")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(theme.accent))
                            }
                            .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface.opacity(0.7)))

                    field("Notes", text: $notes, placeholder: "Recovery codes, PINs…", axis: .vertical)
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default,
                       axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(type.label(9.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(theme.tertiary)
            TextField(placeholder, text: text, axis: axis)
                .font(type.prose(15))
                .foregroundStyle(theme.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .URL)
                .lineLimit(axis == .vertical ? 2...5 : 1...1)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        }
    }

    private func save() {
        var updated = entry
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.website = website.trimmingCharacters(in: .whitespaces)
        updated.username = username
        updated.password = password
        updated.notes = notes
        do {
            try model.vault.upsert(updated)
            Haptics.success()
            dismiss()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
