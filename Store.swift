import Foundation
import SQLite3

// Reads ~/Agent/food/food.db (written by ~/Agent/tools/food). All writes go
// through that CLI so the Telegram agent and this app never disagree.

struct Entry: Identifiable, Hashable {
    let id: Int; let day: String; let ts: Date; let hall: String; let name: String
    let servings: Double; let cals: Double; let protein: Double?; let carbs: Double?; let fat: Double?
}
struct Item: Identifiable, Hashable {
    let id: Int; let hall: String; let name: String
    let cals: Double; let protein: Double?; let carbs: Double?; let fat: Double?; let timesEaten: Int
}
struct HealthDay: Hashable {
    let day: String; let active: Double?; let resting: Double?; let steps: Double?
    let exercise: Double?; let restingHR: Double?; let sleep: Double?; let weight: Double?
    var appleScore: Double? = nil; var estScore: Double? = nil
    var bedtime: String? = nil; var waketime: String? = nil; var wakeups: Double? = nil
    var burned: Double? { active == nil && resting == nil ? nil : (active ?? 0) + (resting ?? 0) }
    /// apple's sleep score when the watch gave one, else our estimate on the same 50/30/20 split
    var sleepScore: Double? { appleScore ?? estScore }
    var scoreIsApple: Bool { appleScore != nil }
}
struct Workout: Identifiable, Hashable {
    let id: Int; let day: String; let start: String; let type: String; let minutes: Double; let cals: Double?
}
struct DayTotal: Identifiable, Hashable {
    var id: String { day }
    let day: String; let cals: Double; let protein: Double; let carbs: Double; let fat: Double
}

enum Day {
    static let rollover = 4
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static var today: String { fmt.string(from: Date().addingTimeInterval(-Double(rollover) * 3600)) }
    static func date(_ s: String) -> Date { fmt.date(from: s) ?? Date() }
    static func offset(_ s: String, _ n: Int) -> String { fmt.string(from: Calendar.current.date(byAdding: .day, value: n, to: date(s))!) }
}

@MainActor
final class Store: ObservableObject {
    nonisolated static let dbPath = ProcessInfo.processInfo.environment["FOOD_DB"] ?? NSHomeDirectory() + "/Agent/food/food.db"
    nonisolated static let tool = NSHomeDirectory() + "/Agent/tools/food"
    nonisolated static let healthDir = NSHomeDirectory() + "/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Health"

    @Published var goal: Double = 2200
    @Published var proteinGoal: Double = 150
    @Published var today: [Entry] = []
    @Published var allEntries: [Entry] = []
    @Published var catalog: [Item] = []
    @Published var totals: [String: DayTotal] = [:]
    @Published var health: [String: HealthDay] = [:]
    @Published var workouts: [Workout] = []
    @Published var lastHealthSync: Date?
    @Published var lastError: String?

    private var lastMTime: Date?
    private var timer: Timer?
    private var syncTimer: Timer?

    init() {
        runTool(["sync"]) { [weak self] _ in self?.reload(force: true) }
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload(force: false) }
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runTool(["sync"]) { _ in self?.reload(force: true) } }
        }
    }

    // MARK: derived
    var todayDay: String { Day.today }
    var eaten: Double { today.reduce(0) { $0 + $1.cals } }
    var left: Double { goal - eaten }
    var todayTotal: DayTotal { totals[todayDay] ?? DayTotal(day: todayDay, cals: 0, protein: 0, carbs: 0, fat: 0) }
    var todayHealth: HealthDay? { health[todayDay] }
    var halls: [String] { Array(Set(catalog.map(\.hall).filter { !$0.isEmpty })).sorted() }

    func days(_ n: Int) -> [String] { (0..<max(n, 1)).reversed().map { Day.offset(todayDay, -$0) } }
    /// number of days from the first logged meal or health record through today
    var allTimeDays: Int {
        let first = (Array(health.keys) + Array(totals.keys)).min() ?? todayDay
        return (Calendar.current.dateComponents([.day], from: Day.date(first), to: Day.date(todayDay)).day ?? 0) + 1
    }

    // MARK: load
    func reload(force: Bool) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.dbPath)
        let m = attrs?[.modificationDate] as? Date
        if !force, let m, m == lastMTime { return }
        lastMTime = m
        guard let db = open() else { return }
        defer { sqlite3_close(db) }

        goal = query(db, "select value from settings where key='goal'") { Double(text($0, 0)) ?? 2200 }.first ?? 2200
        proteinGoal = query(db, "select value from settings where key='protein'") { Double(text($0, 0)) ?? 150 }.first ?? 150

        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; iso.locale = Locale(identifier: "en_US_POSIX")
        allEntries = query(db, "select id, day, ts, coalesce(hall,''), name, servings, cals, protein, carbs, fat from log order by ts desc") { s in
            Entry(id: int(s, 0), day: text(s, 1), ts: iso.date(from: text(s, 2)) ?? Date(), hall: text(s, 3), name: text(s, 4),
                  servings: dbl(s, 5) ?? 1, cals: dbl(s, 6) ?? 0, protein: dbl(s, 7), carbs: dbl(s, 8), fat: dbl(s, 9))
        }
        today = allEntries.filter { $0.day == todayDay }.sorted { $0.ts < $1.ts }

        var t: [String: DayTotal] = [:]
        for r in query(db, "select day, sum(cals), coalesce(sum(protein),0), coalesce(sum(carbs),0), coalesce(sum(fat),0) from log group by day", { s in
            DayTotal(day: text(s, 0), cals: dbl(s, 1) ?? 0, protein: dbl(s, 2) ?? 0, carbs: dbl(s, 3) ?? 0, fat: dbl(s, 4) ?? 0)
        }) { t[r.day] = r }
        totals = t

        catalog = query(db, """
            select c.id, coalesce(c.hall,''), c.name, c.cals, c.protein, c.carbs, c.fat,
              (select count(*) from log l where l.name = c.name and coalesce(l.hall,'') = coalesce(c.hall,''))
            from catalog c order by c.hall, c.name
            """) { s in
            Item(id: int(s, 0), hall: text(s, 1), name: text(s, 2), cals: dbl(s, 3) ?? 0, protein: dbl(s, 4), carbs: dbl(s, 5), fat: dbl(s, 6), timesEaten: int(s, 7))
        }

        var h: [String: HealthDay] = [:]
        let hasScore = !query(db, "select 1 from pragma_table_info('health') where name='apple_sleep_score'") { _ in 1 }.isEmpty
        let extra = hasScore ? "apple_sleep_score, sleep_score, bedtime, waketime, wakeups" : "null, null, null, null, null"
        for r in query(db, "select day, active, resting, steps, exercise, resting_hr, sleep, weight, \(extra) from health", { s in
            HealthDay(day: text(s, 0), active: dbl(s, 1), resting: dbl(s, 2), steps: dbl(s, 3), exercise: dbl(s, 4),
                      restingHR: dbl(s, 5), sleep: dbl(s, 6), weight: dbl(s, 7),
                      appleScore: dbl(s, 8), estScore: dbl(s, 9),
                      bedtime: text(s, 10).isEmpty ? nil : text(s, 10), waketime: text(s, 11).isEmpty ? nil : text(s, 11), wakeups: dbl(s, 12))
        }) { h[r.day] = r }
        health = h
        let updated = query(db, "select max(updated) from health where updated is not null") { text($0, 0) }.first ?? ""
        lastHealthSync = iso.date(from: updated)

        workouts = query(db, "select id, day, start, type, minutes, cals from workouts order by start desc") { s in
            Workout(id: int(s, 0), day: text(s, 1), start: text(s, 2), type: text(s, 3), minutes: dbl(s, 4) ?? 0, cals: dbl(s, 5))
        }
    }

    private func open() -> OpaquePointer? {
        var db: OpaquePointer?
        if !FileManager.default.fileExists(atPath: Self.dbPath) {
            // first launch before anything was logged: let the CLI create the schema
            _ = try? Self.runSync(["goal"])
        }
        guard sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            lastError = "can't open \(Self.dbPath)"; return nil
        }
        return db
    }

    private func query<T>(_ db: OpaquePointer, _ sql: String, _ row: (OpaquePointer) -> T) -> [T] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { return [] }
        defer { sqlite3_finalize(st) }
        var out: [T] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(row(st)) }
        return out
    }

    // MARK: writes (via the CLI)
    nonisolated static var python: String {
        let candidates = ["/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
    }

    nonisolated static func runSync(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [tool] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 { throw NSError(domain: "food", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: s.trimmingCharacters(in: .whitespacesAndNewlines)]) }
        return s
    }

    func runTool(_ args: [String], done: ((String) -> Void)? = nil) {
        Task.detached {
            do {
                let s = try Store.runSync(args)
                await MainActor.run { self.lastError = nil; self.reload(force: true); done?(s) }
            } catch {
                await MainActor.run { self.lastError = error.localizedDescription }
            }
        }
    }

    func eat(name: String, cals: Double?, protein: Double?, carbs: Double?, fat: Double?, hall: String, servings: Double) {
        var a = ["eat", name]
        if let cals { a.append(String(cals)) }
        if let protein { a += ["-p", String(protein)] }
        if let carbs { a += ["-c", String(carbs)] }
        if let fat { a += ["-f", String(fat)] }
        if !hall.isEmpty { a += ["--hall", hall] }
        if servings != 1 { a += ["-s", String(servings)] }
        runTool(a)
    }
    func remove(_ e: Entry) { runTool(["rm", String(e.id)]) }
    func setGoal(_ g: Int) { runTool(["goal", String(g)]) }
    func setProteinGoal(_ g: Int) { runTool(["protein", String(g)]) }
    func logWorkout(type: String, minutes: Double, cals: Double?) {
        var a = ["workout", type, String(minutes)]
        if let cals { a.append(String(cals)) }
        runTool(a)
    }
    func importHealth(_ url: URL) { runTool(["import-health", url.path]) }
    func syncHealth() { runTool(["sync"]) }
}

private func text(_ s: OpaquePointer, _ i: Int32) -> String {
    guard let c = sqlite3_column_text(s, i) else { return "" }
    return String(cString: c)
}
private func dbl(_ s: OpaquePointer, _ i: Int32) -> Double? {
    sqlite3_column_type(s, i) == SQLITE_NULL ? nil : sqlite3_column_double(s, i)
}
private func int(_ s: OpaquePointer, _ i: Int32) -> Int { Int(sqlite3_column_int64(s, i)) }
