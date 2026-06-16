import AppKit
import Combine
import EventKit
import IOKit.ps
import SwiftUI
import UniformTypeIdentifiers

struct HorizonBatterySnapshot: Equatable {
    var percentage: Int?
    var isCharging: Bool
    var powerSource: String
    var minutesToFullCharge: Int?

    static let unavailable = HorizonBatterySnapshot(
        percentage: nil,
        isCharging: false,
        powerSource: "Power",
        minutesToFullCharge: nil
    )

    var title: String {
        if let percentage {
            return "\(percentage)%"
        }

        return powerSource
    }

    var subtitle: String {
        let mode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "Low Power" : "Normal Power"
        if isCharging {
            if let minutesToFullCharge, minutesToFullCharge > 0 {
                return "Full in \(minutesToFullCharge)m · \(mode)"
            }
            return "Charging · \(mode)"
        }

        return "\(powerSource) · \(mode)"
    }

    var symbolName: String {
        if isCharging {
            return "battery.100.bolt"
        }

        guard let percentage else {
            return "bolt.horizontal"
        }

        switch percentage {
        case 80 ... 100:
            return "battery.100"
        case 40 ..< 80:
            return "battery.50"
        case 1 ..< 40:
            return "battery.25"
        default:
            return "battery.0"
        }
    }
}

struct HorizonShelfItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let url: URL
    let addedAt: Date
    let bookmarkData: Data?
    let bookmarkIsStale: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case addedAt
        case bookmarkData
        case bookmarkIsStale
    }

    init(
        id: UUID = UUID(),
        url: URL,
        addedAt: Date,
        bookmarkData: Data? = nil,
        bookmarkIsStale: Bool = false
    ) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
        self.bookmarkIsStale = bookmarkIsStale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.url = try container.decode(URL.self, forKey: .url)
        self.addedAt = try container.decode(Date.self, forKey: .addedAt)
        self.bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        self.bookmarkIsStale = try container.decodeIfPresent(Bool.self, forKey: .bookmarkIsStale) ?? false
    }

    var title: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var subtitle: String {
        url.deletingLastPathComponent().lastPathComponent
    }

    var symbolName: String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return "folder"
        }

        return "doc"
    }

    var accessStatusText: String {
        bookmarkIsStale ? "Bookmark needs refresh" : subtitle
    }

    var previewImage: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 34, height: 34)
        return image
    }
}

@MainActor
final class HorizonModuleModel: ObservableObject, IslandModule {
    static let moduleID = "horizon"

    let id = HorizonModuleModel.moduleID
    let title = "Horizon"
    let symbolName = "sun.horizon"

    @Published private(set) var now = Date()
    @Published private(set) var calendarStatus = "Calendar"
    @Published private(set) var nextEventTitle = "No upcoming event"
    @Published private(set) var nextEventTime = "--"
    @Published private(set) var reminderStatus = "Reminders"
    @Published private(set) var nextReminderTitle = "No due reminder"
    @Published private(set) var nextReminderTime = "--"
    @Published private(set) var batterySnapshot = HorizonBatterySnapshot.unavailable
    @Published private(set) var shelfItems: [HorizonShelfItem] = []

    let weatherService = HorizonWeatherService()
    let timerController = HorizonTimerController()

    private let eventStore = EKEventStore()
    private let shelfStoreURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Fantastic Island/horizon-shelf.json")
    private var timer: Timer?
    private var lastCalendarRefresh = Date.distantPast
    private var lastReminderRefresh = Date.distantPast

    init() {
        refreshClock()
        refreshBattery()
        loadShelfItems()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.time",
                moduleID: id,
                title: "Local time",
                text: now.formatted(date: .omitted, time: .shortened),
                isEnabledByDefault: true
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.event",
                moduleID: id,
                title: "Next event",
                text: nextEventTime,
                isEnabledByDefault: false
            ),
            CollapsedSummaryItem(
                id: "\(id).summary.weather",
                moduleID: id,
                title: "Weather",
                text: weatherSummaryText,
                isEnabledByDefault: false
            ),
        ]
    }

    var weatherSummaryText: String {
        if let temperature = weatherService.snapshot.temperatureCelsius {
            return "\(Int(temperature.rounded()))°"
        }

        return weatherService.snapshot.conditionText
    }

    var taskActivityContribution: TaskActivityContribution {
        TaskActivityContribution()
    }

    var preferredOpenedContentHeight: CGFloat { 146 }

    var allowsInternalScrolling: Bool { false }

    func makeLiveContentView(presentation _: IslandModulePresentationContext) -> AnyView {
        AnyView(HorizonModuleContentView(model: self))
    }

    var timeText: String {
        now.formatted(date: .omitted, time: .shortened)
    }

    var dateText: String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    func addShelfURLs(_ urls: [URL]) {
        let existing = Set(shelfItems.map(\.url))
        let newItems = urls
            .filter { !existing.contains($0) }
            .map { makeShelfItem(for: $0, addedAt: .now) }

        guard !newItems.isEmpty else {
            return
        }

        shelfItems = Array((newItems + shelfItems).prefix(5))
        persistShelfItems()
    }

    func removeShelfItem(_ item: HorizonShelfItem) {
        shelfItems.removeAll { $0.id == item.id }
        persistShelfItems()
    }

    func openShelfItem(_ item: HorizonShelfItem) {
        performWithShelfItemAccess(item) { url in
            NSWorkspace.shared.open(url)
        }
    }

    func revealShelfItem(_ item: HorizonShelfItem) {
        performWithShelfItemAccess(item) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func quickLookShelfItem(_ item: HorizonShelfItem) {
        performWithShelfItemAccess(item) { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            process.arguments = ["-p", url.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }

    func shareShelfItem(_ item: HorizonShelfItem) {
        performWithShelfItemAccess(item) { url in
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: [url])
                return
            }

            let picker = NSSharingServicePicker(items: [url])
            if let view = NSApp.keyWindow?.contentView ?? NSApp.windows.first(where: \.isVisible)?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    func activateForUserIntent() {
        weatherService.refreshIfNeeded(force: true, requestAuthorizationIfNeeded: true)
        requestCalendarAccessIfNeeded()
        requestReminderAccessIfNeeded()
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClock()
                self?.refreshBattery()
                self?.weatherService.refreshIfNeeded()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func loadShelfItems() {
        guard FileManager.default.fileExists(atPath: shelfStoreURL.path),
              let data = try? Data(contentsOf: shelfStoreURL),
              let decoded = try? JSONDecoder().decode([HorizonShelfItem].self, from: data) else {
            return
        }

        let resolvedItems = Array(decoded.compactMap(resolveShelfItem(_:)).prefix(5))
        shelfItems = resolvedItems

        if resolvedItems != Array(decoded.prefix(5)) {
            persistShelfItems()
        }
    }

    private func persistShelfItems() {
        do {
            try FileManager.default.createDirectory(at: shelfStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(shelfItems)
            try data.write(to: shelfStoreURL, options: .atomic)
        } catch {
            NSLog("Fantastic Island shelf persistence failed: %@", error.localizedDescription)
        }
    }

    private func makeShelfItem(for url: URL, addedAt: Date) -> HorizonShelfItem {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return HorizonShelfItem(
            url: url,
            addedAt: addedAt,
            bookmarkData: bookmarkData
        )
    }

    private func resolveShelfItem(_ item: HorizonShelfItem) -> HorizonShelfItem? {
        guard let bookmarkData = item.bookmarkData else {
            return FileManager.default.fileExists(atPath: item.url.path) ? item : nil
        }

        var isStale = false
        let resolvedURL: URL
        do {
            resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return FileManager.default.fileExists(atPath: item.url.path) ? item : nil
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return nil
        }

        if isStale {
            let refreshedItem = makeShelfItem(for: resolvedURL, addedAt: item.addedAt)
            return HorizonShelfItem(
                id: item.id,
                url: refreshedItem.url,
                addedAt: refreshedItem.addedAt,
                bookmarkData: refreshedItem.bookmarkData ?? bookmarkData,
                bookmarkIsStale: refreshedItem.bookmarkData == nil
            )
        }

        return HorizonShelfItem(
            id: item.id,
            url: resolvedURL,
            addedAt: item.addedAt,
            bookmarkData: bookmarkData,
            bookmarkIsStale: false
        )
    }

    private func performWithShelfItemAccess(_ item: HorizonShelfItem, action: (URL) -> Void) {
        let didAccess = item.url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                item.url.stopAccessingSecurityScopedResource()
            }
        }

        action(item.url)
    }

    private func refreshClock() {
        now = .now
        if now.timeIntervalSince(lastCalendarRefresh) > 300 {
            refreshCalendar()
        }
        if now.timeIntervalSince(lastReminderRefresh) > 300 {
            refreshReminders()
        }
    }

    private func requestCalendarAccessIfNeeded() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.calendarStatus = granted ? "Calendar Ready" : "Calendar Locked"
                        self?.refreshCalendar()
                    }
                }
            } else {
                eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.calendarStatus = granted ? "Calendar Ready" : "Calendar Locked"
                        self?.refreshCalendar()
                    }
                }
            }
        case .denied, .restricted, .writeOnly:
            calendarStatus = "Calendar Locked"
        default:
            if Self.hasReadableAccess(for: .event) {
                calendarStatus = "Calendar Ready"
                refreshCalendar()
            } else {
                calendarStatus = "Calendar"
            }
        }
    }

    private func requestReminderAccessIfNeeded() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .notDetermined:
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToReminders { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.reminderStatus = granted ? "Reminders Ready" : "Reminders Locked"
                        self?.refreshReminders()
                    }
                }
            } else {
                eventStore.requestAccess(to: .reminder) { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.reminderStatus = granted ? "Reminders Ready" : "Reminders Locked"
                        self?.refreshReminders()
                    }
                }
            }
        case .denied, .restricted, .writeOnly:
            reminderStatus = "Reminders Locked"
        default:
            if Self.hasReadableAccess(for: .reminder) {
                reminderStatus = "Reminders Ready"
                refreshReminders()
            } else {
                reminderStatus = "Reminders"
            }
        }
    }

    private func refreshCalendar() {
        lastCalendarRefresh = now
        guard Self.hasReadableAccess(for: .event) else {
            nextEventTitle = "Calendar access needed"
            nextEventTime = "--"
            return
        }

        let start = now
        let end = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 12, to: start) ?? start.addingTimeInterval(43_200)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        guard let event = events.first else {
            nextEventTitle = "No upcoming event"
            nextEventTime = "--"
            return
        }

        nextEventTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? event.title
            : "Untitled event"
        nextEventTime = event.startDate.formatted(date: .omitted, time: .shortened)
    }

    private func refreshReminders() {
        lastReminderRefresh = now
        guard Self.hasReadableAccess(for: .reminder) else {
            nextReminderTitle = "Reminders access needed"
            nextReminderTime = "--"
            return
        }

        let end = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604_800)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: end,
            calendars: nil
        )

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor [weak self] in
                self?.applyReminderSnapshot(reminders ?? [])
            }
        }
    }

    private func applyReminderSnapshot(_ reminders: [EKReminder]) {
        let sorted = reminders.sorted { lhs, rhs in
            let lhsDate = lhs.dueDateComponents?.date ?? .distantFuture
            let rhsDate = rhs.dueDateComponents?.date ?? .distantFuture
            return lhsDate < rhsDate
        }

        guard let reminder = sorted.first else {
            nextReminderTitle = "No due reminder"
            nextReminderTime = "--"
            return
        }

        nextReminderTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled reminder"
            : reminder.title

        if let date = reminder.dueDateComponents?.date {
            nextReminderTime = date.formatted(date: .abbreviated, time: .shortened)
        } else {
            nextReminderTime = "Soon"
        }
    }

    private func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            batterySnapshot = .unavailable
            return
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int
        let percentage: Int?
        if let currentCapacity, let maxCapacity, maxCapacity > 0 {
            percentage = Int(round((Double(currentCapacity) / Double(maxCapacity)) * 100))
        } else {
            percentage = nil
        }

        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let minutesToFull: Int?
        if isCharging, let rawMinutes = description[kIOPSTimeToFullChargeKey] as? Int, rawMinutes > 0 {
            minutesToFull = rawMinutes
        } else {
            minutesToFull = nil
        }

        batterySnapshot = HorizonBatterySnapshot(
            percentage: percentage,
            isCharging: isCharging,
            powerSource: description[kIOPSPowerSourceStateKey] as? String ?? "Battery",
            minutesToFullCharge: minutesToFull
        )
    }

    private static func hasReadableAccess(for entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }

        return status.rawValue == 3
    }
}

@MainActor
final class TimerModuleModel: ObservableObject, IslandModule {
    static let moduleID = "timer"

    let id = TimerModuleModel.moduleID
    let title = "Timer"
    let symbolName = "timer"
    let timerController: HorizonTimerController

    private var cancellables: Set<AnyCancellable> = []

    init(timerController: HorizonTimerController) {
        self.timerController = timerController
        timerController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.remaining",
                moduleID: id,
                title: "Timer",
                text: timerController.snapshot.mode == .idle ? "Ready" : timerController.snapshot.displayText,
                isEnabledByDefault: false
            ),
        ]
    }

    var islandActivities: [IslandActivity] {
        guard timerController.snapshot.mode == .completed else {
            return []
        }

        let completedAt = timerController.completionDate ?? .now
        return [
            IslandActivity(
                id: "\(id).timer.completed",
                moduleID: id,
                sourceID: "timer.completed",
                kind: .actionRequired,
                priority: 45,
                createdAt: completedAt,
                updatedAt: completedAt,
                presentationPolicy: IslandActivityPresentationPolicy(
                    autoPresentationScope: .global,
                    autoDismissDelay: nil
                )
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution {
        let snapshot = timerController.snapshot
        let lastEventAt = snapshot.mode == .idle ? nil : (timerController.completionDate ?? .now)
        return TaskActivityContribution(
            activeTaskCount: snapshot.mode == .idle ? 0 : 1,
            inProgressTaskCount: snapshot.mode == .running ? 1 : 0,
            lastEventAt: lastEventAt
        )
    }

    var preferredOpenedContentHeight: CGFloat { 144 }
    var allowsInternalScrolling: Bool { false }

    func makeLiveContentView(presentation _: IslandModulePresentationContext) -> AnyView {
        AnyView(TimerModuleContentView(controller: timerController))
    }
}

@MainActor
final class ShelfModuleModel: ObservableObject, IslandModule {
    static let moduleID = "shelf"

    let id = ShelfModuleModel.moduleID
    let title = "Shelf"
    let symbolName = "tray.and.arrow.down"
    let horizonModule: HorizonModuleModel

    private var cancellables: Set<AnyCancellable> = []

    init(horizonModule: HorizonModuleModel) {
        self.horizonModule = horizonModule
        horizonModule.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var collapsedSummaryItems: [CollapsedSummaryItem] {
        [
            CollapsedSummaryItem(
                id: "\(id).summary.count",
                moduleID: id,
                title: "Shelf",
                text: "\(horizonModule.shelfItems.count)/5",
                isEnabledByDefault: false
            ),
        ]
    }

    var taskActivityContribution: TaskActivityContribution { TaskActivityContribution() }
    var preferredOpenedContentHeight: CGFloat { 162 }
    var allowsInternalScrolling: Bool { false }

    func makeLiveContentView(presentation _: IslandModulePresentationContext) -> AnyView {
        AnyView(ShelfModuleContentView(model: horizonModule))
    }
}

private struct HorizonModuleContentView: View {
    @ObservedObject var model: HorizonModuleModel

    private let columns = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            HorizonGlanceTile(
                symbolName: "clock",
                label: "Now",
                value: model.timeText,
                detail: model.dateText
            )

            HorizonGlanceTile(
                symbolName: model.weatherService.snapshot.conditionSymbol,
                label: model.weatherService.snapshot.locationLabel,
                value: weatherValueText,
                detail: model.weatherService.snapshot.conditionText
            )

            HorizonGlanceTile(
                symbolName: "calendar",
                label: model.calendarStatus,
                value: model.nextEventTime,
                detail: model.nextEventTitle
            )

            HorizonGlanceTile(
                symbolName: "checklist",
                label: model.reminderStatus,
                value: model.nextReminderTime,
                detail: model.nextReminderTitle
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weatherValueText: String {
        if let temperature = model.weatherService.snapshot.temperatureCelsius {
            return "\(Int(temperature.rounded()))°"
        }

        return "Weather"
    }
}

private struct HorizonGlanceTile: View {
    let symbolName: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .frame(width: 13, alignment: .center)

                Text(label)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
        }
    }
}

private struct TimerModuleContentView: View {
    @ObservedObject var controller: HorizonTimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: controller.snapshot.mode == .idle ? 0 : controller.snapshot.progressFraction)
                        .stroke(timerTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: controller.snapshot.mode == .completed ? "checkmark" : "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(timerTint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.snapshot.displayText)
                        .font(.system(size: 21, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)

                    Text(timerStatusText)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if controller.snapshot.mode == .running {
                        timerIconButton("pause.fill", label: "Pause") { controller.pause() }
                    } else if controller.snapshot.mode == .paused {
                        timerIconButton("play.fill", label: "Resume") { controller.resume() }
                    }

                    if controller.snapshot.mode != .idle {
                        timerIconButton("arrow.counterclockwise", label: "Reset") { controller.reset() }
                    }

                    timerIconButton("clock", label: "Open Clock") { _ = controller.openNativeClockApp() }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.055))
                    Capsule()
                        .fill(timerTint.opacity(0.72))
                        .frame(width: max(4, proxy.size.width * controller.snapshot.progressFraction))
                }
            }
            .frame(height: 4)

            HStack(spacing: 5) {
                ForEach(HorizonTimerController.islandPresetMinutes, id: \.self) { minutes in
                    Button("\(minutes)m") {
                        controller.start(minutes: minutes)
                    }
                    .buttonStyle(HorizonTimerButtonStyle(isSelected: selectedPresetMinutes == minutes))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timerTint: Color {
        switch controller.snapshot.mode {
        case .idle:
            return .white.opacity(0.42)
        case .running:
            return IslandVisualLanguage.accent.opacity(0.92)
        case .paused:
            return Color.yellow.opacity(0.86)
        case .completed:
            return Color.green.opacity(0.9)
        }
    }

    private var selectedPresetMinutes: Int? {
        controller.snapshot.mode == .idle ? nil : controller.snapshot.presetMinutes
    }

    private var timerStatusText: String {
        switch controller.snapshot.mode {
        case .idle:
            return "READY"
        case .running:
            return "\(controller.snapshot.presetMinutes) MIN RUNNING"
        case .paused:
            return "PAUSED"
        case .completed:
            return "COMPLETE"
        }
    }

    private func timerIconButton(_ symbolName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 10.5, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(label)
    }
}

private struct ShelfModuleContentView: View {
    @ObservedObject var model: HorizonModuleModel
    @State private var isShelfDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.white.opacity(0.68))
                Text("Shelf")
                    .font(IslandVisualLanguage.islandLabel(11.5))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                Text("\(model.shelfItems.count)/5")
                    .font(IslandVisualLanguage.islandLabel(11))
                    .foregroundStyle(.white.opacity(0.42))
            }

            if model.shelfItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isShelfDropTargeted ? IslandVisualLanguage.accent.opacity(0.9) : .white.opacity(0.38))

                    Text("Drop files here")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isShelfDropTargeted ? .white.opacity(0.78) : .white.opacity(0.48))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.white.opacity(isShelfDropTargeted ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isShelfDropTargeted ? IslandVisualLanguage.accent.opacity(0.28) : Color.white.opacity(0.07),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                }
            } else {
                HStack(spacing: 7) {
                    ForEach(Array(model.shelfItems.prefix(4))) { item in
                        HorizonShelfChip(item: item) {
                            model.openShelfItem(item)
                        } quickLook: {
                            model.quickLookShelfItem(item)
                        } reveal: {
                            model.revealShelfItem(item)
                        } share: {
                            model.shareShelfItem(item)
                        } remove: {
                            model.removeShelfItem(item)
                        }
                    }

                    if model.shelfItems.count > 4 {
                        Text("+\(model.shelfItems.count - 4)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .frame(height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isShelfDropTargeted ? IslandVisualLanguage.accent.opacity(0.1) : Color.clear)
        )
        .overlay(alignment: .top) {
            if isShelfDropTargeted {
                Rectangle()
                    .fill(IslandVisualLanguage.accent.opacity(0.12))
                    .frame(height: 1)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isShelfDropTargeted,
            perform: handleShelfDrop(providers:)
        )
    }

    private func handleShelfDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else {
            return false
        }

        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = Self.fileURL(from: item) else {
                    return
                }

                Task { @MainActor in
                    model.addShelfURLs([url])
                }
            }
        }

        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private struct HorizonStatusCard: View {
    let symbolName: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: symbolName)
                    .foregroundStyle(.white.opacity(0.6))
                Text(label)
                    .font(IslandVisualLanguage.islandLabel(10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value)
                    .font(IslandVisualLanguage.islandLabel(11))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 50, alignment: .leading)
                    .lineLimit(1)

                Text(detail)
                    .font(IslandVisualLanguage.islandBody(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
    }
}

private struct HorizonWeatherPill: View {
    let snapshot: HorizonWeatherSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.conditionSymbol)
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .trailing, spacing: 1) {
                if let temperature = snapshot.temperatureCelsius {
                    Text("\(Int(temperature.rounded()))°")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                } else {
                    Text(snapshot.conditionText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                Text(snapshot.locationLabel)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white.opacity(0.78))
    }
}

private struct HorizonBatteryPill: View {
    let snapshot: HorizonBatterySnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .trailing, spacing: 1) {
                Text(snapshot.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(snapshot.subtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white.opacity(0.78))
    }
}

private struct HorizonShelfChip: View {
    let item: HorizonShelfItem
    let open: () -> Void
    let quickLook: () -> Void
    let reveal: () -> Void
    let share: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                Image(nsImage: item.previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: 76, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Quick Look", action: quickLook)
            Button("Reveal in Finder", action: reveal)
            Button("Share", action: share)
            Divider()
            Button("Remove", role: .destructive, action: remove)
        }
        .help(item.accessStatusText)
    }
}

private struct HorizonTimerButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(configuration.isPressed || isSelected ? 0.94 : 0.64))
            .frame(minWidth: 34, minHeight: 22)
            .padding(.horizontal, 3)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.1 : (isSelected ? 0.085 : 0.04)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.11 : 0.055), lineWidth: 0.7)
            }
    }
}

private struct HorizonShelfButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.88 : 0.5))
            .frame(width: 22, height: 22)
    }
}
