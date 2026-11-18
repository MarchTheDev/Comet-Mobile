//
//  CalendarScreen.swift
//  Comet
//
//  The workspace's own calendar: a month you can walk through, a day that lists
//  what is on it, and an event sheet that is three fields long. Events stay on
//  this device in the workspace profile and export as a standard .ics.
//

import SwiftUI

struct CalendarScreen: View {
    /// Nil when Calendar is one of the bar's own screens.
    var close: (() -> Void)? = nil

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type

    @State private var month = CalendarMath.startOfMonth(Date())
    @State private var selected = Date()
    @State private var editing: CalendarEvent?
    @State private var showingEditor = false

    private var grid: [Date] {
        CalendarMath.monthGrid(for: month, weekStartsOnMonday: model.settings.weekStartsMonday)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        return formatter.string(from: month)
    }

    private var selectedEvents: [CalendarEvent] { model.events(on: selected) }

    var body: some View {
        ZStack(alignment: .top) {
            ModuleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ModuleHeader(eyebrow: "Comet", title: monthTitle, subtitle: subtitle, close: close) {
                        HStack(spacing: 8) {
                            if let url = model.calendarExportURL() {
                                ShareLink(item: url) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.ink)
                                        .frame(width: 38, height: 38)
                                        .glassPanel(radius: 19)
                                }
                            }
                            Button {
                                Haptics.press()
                                editing = nil
                                showingEditor = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(theme.onAccent)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(theme.accentGradient))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("New event")
                        }
                    }

                    monthControls
                    monthGrid
                    daySection
                    Text("Events live in this workspace's profile on this device. Export writes a standard .ics for anything else.")
                        .font(type.prose(11))
                        .foregroundStyle(theme.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showingEditor) {
            EventSheet(event: editing, initialDate: selected)
                .environmentObject(model)
                .environment(\.comet, theme)
                .environment(\.type, type)
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationCornerRadius(34)
        }
    }

    private var subtitle: String {
        let count = model.events.count
        return count == 1 ? "1 event on this device" : "\(count) events on this device"
    }

    private var monthControls: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.surface))
            }
            .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))

            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    month = CalendarMath.startOfMonth(Date())
                    selected = Date()
                }
            } label: {
                Text("Today")
                    .font(type.label(12.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(Capsule().fill(theme.accent.opacity(0.13)))
            }
            .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))

            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.surface))
            }
            .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var monthGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                let weekdays = model.settings.weekStartsMonday
                    ? ["M", "T", "W", "T", "F", "S", "S"]
                    : ["S", "M", "T", "W", "T", "F", "S"]
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(type.label(10.5, weight: .bold))
                        .foregroundStyle(theme.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(grid, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(12)
        .cometCard(radius: 26, lift: 0.55)
        .padding(.horizontal, 20)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = CalendarMath.isSameDay(day, selected)
        let isToday = CalendarMath.isSameDay(day, Date())
        let count = model.events(on: day).count

        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { selected = day }
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(type.label(14, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? theme.onAccent : (inMonth ? theme.ink : theme.tertiary.opacity(0.5)))
                Circle()
                    .fill(isSelected ? theme.onAccent : theme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(count > 0 ? (isSelected ? 0.9 : 1) : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(theme.accentGradient)
                          : (isToday ? AnyShapeStyle(theme.accent.opacity(0.12)) : AnyShapeStyle(Color.clear)))
            )
        }
        .buttonStyle(PressableStyle(scale: 0.92, haptic: nil))
    }

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: dayTitle, trailing: selectedEvents.isEmpty ? nil : "\(selectedEvents.count)")
                Spacer()
                Button {
                    Haptics.tap()
                    editing = nil
                    showingEditor = true
                } label: {
                    Text("Add")
                        .font(type.label(12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(theme.accent.opacity(0.12)))
                }
                .buttonStyle(PressableStyle(scale: 0.95, haptic: nil))
            }

            if selectedEvents.isEmpty {
                Button {
                    Haptics.tap()
                    editing = nil
                    showingEditor = true
                } label: {
                    HStack(spacing: 10) {
                        Glyph(symbol: "calendar.badge.plus", size: 38)
                        Text("Nothing on this day")
                            .font(type.prose(13.5))
                            .foregroundStyle(theme.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .cometCard(radius: 20, lift: 0.35)
                }
                .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(selectedEvents.enumerated()), id: \.element.id) { index, event in
                        Button {
                            Haptics.tap()
                            editing = event
                            showingEditor = true
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(event.time.isEmpty ? "all day" : event.time)
                                    .font(type.mono(11, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 54, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title)
                                        .font(type.title(15))
                                        .foregroundStyle(theme.ink)
                                        .multilineTextAlignment(.leading)
                                    if !event.notes.isEmpty {
                                        Text(event.notes)
                                            .font(type.prose(12))
                                            .foregroundStyle(theme.tertiary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .cometCard(radius: 20, lift: 0.35)
                        }
                        .buttonStyle(PressableStyle(scale: 0.99, haptic: nil))
                        .contextMenu {
                            Button {
                                editing = event
                                showingEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.deleteEvent(event)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .stagger(index)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: selected)
    }
}

// MARK: - Event sheet

struct EventSheet: View {
    let event: CalendarEvent?
    let initialDate: Date

    @EnvironmentObject private var model: CometModel
    @Environment(\.comet) private var theme
    @Environment(\.type) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var notes: String

    init(event: CalendarEvent?, initialDate: Date) {
        self.event = event
        self.initialDate = initialDate
        let start = event?.date ?? initialDate
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: start)
        _hasTime = State(initialValue: event?.hasTime ?? false)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: start)
        if let event, event.hasTime {
            let parts = event.time.components(separatedBy: ":")
            components.hour = Int(parts.first ?? "9") ?? 9
            components.minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        } else {
            components.hour = 9
            components.minute = 0
        }
        _time = State(initialValue: Calendar.current.date(from: components) ?? start)
        _notes = State(initialValue: event?.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack {
                Text(event == nil ? "New event" : "Edit event")
                    .font(type.display(24))
                    .foregroundStyle(theme.ink)
                Spacer()
                if let event {
                    Button(role: .destructive) {
                        model.deleteEvent(event)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(theme.raised))
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            TextField("What is it?", text: $title)
                .font(type.prose(17, weight: .medium))
                .foregroundStyle(theme.ink)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))

            DatePicker("Day", selection: $date, displayedComponents: .date)
                .font(type.prose(14))
                .tint(theme.accent)

            Toggle("Set a time", isOn: $hasTime)
                .font(type.prose(14))
                .tint(theme.accent)

            if hasTime {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .font(type.prose(14))
                    .tint(theme.accent)
            }

            TextField("Notes", text: $notes, axis: .vertical)
                .font(type.prose(13.5))
                .foregroundStyle(theme.ink)
                .lineLimit(2...5)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.raised))

            Button(action: save) {
                Text("Save event")
                    .font(type.label(15, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(theme.accentGradient))
            }
            .buttonStyle(PressableStyle())
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.canvasGradient.ignoresSafeArea())
    }

    private func save() {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let key = CometDate.key(date)
        var timeString = ""
        if hasTime {
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            timeString = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
        }
        let updated = CalendarEvent(id: event?.id ?? UUID().uuidString,
                                    title: clean,
                                    dateKey: key,
                                    time: timeString,
                                    notes: notes)
        model.saveEvent(updated)
        dismiss()
    }
}
