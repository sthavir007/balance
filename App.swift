import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: theme — same bones as sthavir.xyz (serif, lowercase, hairline rules, hexagon nodes), in a calm sky blue
enum Theme {
    static let bg = Color(hex: 0xE8F2FA)        // pale sky
    static let surface = Color(hex: 0xF4F9FD)   // slightly lifted panels
    static let rule = Color(hex: 0xC5D9E8)      // hairlines
    static let ink = Color(hex: 0x1D2D3A)       // deep slate
    static let ink2 = Color(hex: 0x4E6577)
    static let muted = Color(hex: 0x8DA2B2)
    static let grid = Color(hex: 0xD7E5F0)
    static let sky = Color(hex: 0x3F8FCB)       // accent, like the red links on the site
    static let intake = sky
    static let burned = Color(hex: 0xD98C66)    // soft clay
    static let aqua = Color(hex: 0x4FAE9C)      // deficit
    static let violet = Color(hex: 0x7486D2)    // periwinkle
    static let yellow = Color(hex: 0xD9A441)
    static let over = Color(hex: 0xD0605A)      // always paired with a label
    static let protein = sky, carbs = burned, fat = aqua
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}

extension Font {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// x domain covering every day in the range, so a single data point stays one bar wide
func dayDomain(_ days: [String]) -> ClosedRange<Date> {
    let a = Day.date(days.first ?? Day.today), b = Day.date(days.last ?? Day.today)
    return a...Calendar.current.date(byAdding: .day, value: 1, to: b)!
}

/// ~6 evenly spaced day labels whatever the range
func dayStride(_ days: [String]) -> Int { max(1, Int((Double(days.count) / 6).rounded(.up))) }

func n(_ x: Double?, _ digits: Int = 0) -> String {
    guard let x else { return "–" }
    return x.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic))
}

func hm(_ hours: Double?) -> String {
    guard let hours else { return "–" }
    let m = Int((hours * 60).rounded())
    return "\(m / 60)h \(String(format: "%02d", m % 60))m"
}

/// "23:40" -> "11:40 pm"
func clock(_ s: String?) -> String {
    guard let s, let h = Int(s.prefix(2)), let m = Int(s.suffix(2)) else { return "–" }
    return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m)) \(h < 12 ? "am" : "pm")"
}

@main
struct BalanceApp: App {
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Balance", id: "main") {
            ContentView().environmentObject(store)
                .focusEffectDisabled()  // no keyboard-focus ring around the text links
                .frame(minWidth: 900, minHeight: 640)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 800)

        MenuBarExtra {
            MenuBarView().environmentObject(store).focusEffectDisabled().preferredColorScheme(.light)
        } label: {
            Text(store.left >= 0 ? "\(n(store.left)) left" : "\(n(-store.left)) over")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            NSApp.setActivationPolicy(.prohibited)
            MainActor.assumeIsolated { Snapshot.run(args[i + 1]) }
        }
        if CommandLine.arguments.contains("--background") {
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async { NSApp.windows.filter { $0.title == "Balance" }.forEach { $0.close() } }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        return true
    }
}

// MARK: shell
enum Section: String, CaseIterable, Identifiable {
    case today, trends, foods, history
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var section: Section = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("balance").font(.serif(44)).foregroundStyle(Theme.ink).tracking(-0.4)
                    Spacer()
                    if let e = store.lastError { Text(e).font(.caption).foregroundStyle(Theme.over).lineLimit(1).frame(maxWidth: 260) }
                }
                Rule().padding(.top, 14).padding(.bottom, 14)
                HStack(spacing: 22) {
                    ForEach(Section.allCases) { s in
                        Button { section = s } label: {
                            Text(s.rawValue).font(.serif(17))
                                .foregroundStyle(section == s ? Theme.sky : Theme.ink2)
                                .underline(section == s, color: Theme.sky)
                        }.buttonStyle(.plain).focusable(false)
                    }
                    Spacer()
                }
                .padding(.bottom, 30)

                Group {
                    switch section {
                    case .today: TodayView()
                    case .trends: TrendsView()
                    case .foods: FoodsView()
                    case .history: HistoryView()
                    }
                }
            }
            .padding(.horizontal, 48).padding(.top, 40).padding(.bottom, 48)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }
}

// MARK: building blocks
struct Rule: View {
    var body: some View { Rectangle().fill(Theme.rule).frame(height: 1) }
}

struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w / 2, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.25)); p.addLine(to: CGPoint(x: w, y: h * 0.75))
        p.addLine(to: CGPoint(x: w / 2, y: h)); p.addLine(to: CGPoint(x: 0, y: h * 0.75)); p.addLine(to: CGPoint(x: 0, y: h * 0.25))
        p.closeSubpath()
        return p
    }
}

/// section heading with the hexagon node from the site
struct Heading: View {
    let text: String; var trailing: String? = nil
    init(_ text: String, trailing: String? = nil) { self.text = text; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Hexagon().stroke(Theme.muted, lineWidth: 1.1).frame(width: 11, height: 12.5).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text).font(.serif(20)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing { Text(trailing).font(.callout).foregroundStyle(Theme.muted) }
        }
    }
}

struct LinkButton: View {
    let title: String; let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.serif(15)).foregroundStyle(Theme.sky).underline(!hover, color: Theme.sky.opacity(0.6))
        }
        .buttonStyle(.plain).focusable(false).onHover { hover = $0 }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.rule, lineWidth: 1))
    }
}

/// a quiet number: small lowercase label over a serif figure
struct Figure: View {
    let label: String; let value: String; var sub: String? = nil; var color: Color = Theme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(Theme.ink2)
            Text(value).font(.serif(28)).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Bar: View {
    let fraction: Double; var color: Color = Theme.sky; var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.grid)
                Capsule().fill(color).frame(width: g.size.width * min(max(fraction, 0), 1))
            }
        }.frame(height: height)
    }
}

struct RangePicker: View {
    @Binding var range: Int
    let options: [(String, Int)] = [("7d", 7), ("30d", 30), ("90d", 90), ("1y", 365), ("all", -1)]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(options, id: \.1) { label, v in
                Button { range = v } label: {
                    Text(label).font(.serif(15)).foregroundStyle(range == v ? Theme.sky : Theme.muted).underline(range == v, color: Theme.sky)
                }.buttonStyle(.plain).focusable(false)
            }
        }
    }
}

// MARK: today
struct TodayView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let t = store.todayTotal, h = store.todayHealth
        let left = store.left
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased())
                    .font(.serif(17)).foregroundStyle(Theme.ink2)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(n(abs(left))).font(.serif(72)).foregroundStyle(left >= 0 ? Theme.ink : Theme.over).monospacedDigit()
                    Text(left >= 0 ? "calories left" : "calories over").font(.serif(22)).foregroundStyle(Theme.ink2)
                }
                Bar(fraction: store.goal > 0 ? store.eaten / store.goal : 0, color: left >= 0 ? Theme.sky : Theme.over, height: 8)
                    .frame(maxWidth: 560)
                Text("\(n(store.eaten)) eaten of \(n(store.goal))" + (h?.burned.map { " · \(n($0)) burned so far" } ?? ""))
                    .font(.callout).foregroundStyle(Theme.muted)
            }

            Panel {
                HStack(alignment: .top, spacing: 18) {
                    Figure(label: "burned", value: n(h?.burned), sub: h?.burned == nil ? "no watch data yet" : "\(n(h?.active)) active + \(n(h?.resting)) resting")
                    Figure(label: "steps", value: n(h?.steps))
                    Figure(label: "exercise", value: h?.exercise == nil ? "–" : "\(n(h?.exercise)) min")
                    Figure(label: "resting hr", value: h?.restingHR == nil ? "–" : "\(n(h?.restingHR))", sub: "bpm")
                }
            }

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 14) {
                    Heading("meals", trailing: store.today.isEmpty ? nil : "\(store.today.count) items")
                    if store.today.isEmpty {
                        Text("nothing logged yet. text the agent a picture of your food.").foregroundStyle(Theme.muted)
                    }
                    ForEach(mealGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(group.0).font(.serif(15)).foregroundStyle(Theme.ink2)
                                Spacer()
                                Text("\(n(group.1.reduce(0) { $0 + $1.cals })) cal").font(.callout).foregroundStyle(Theme.muted).monospacedDigit()
                            }
                            ForEach(group.1) { e in EntryRow(e: e) }
                        }
                        Rule()
                    }
                    let ws = store.workouts.filter { $0.day == store.todayDay }
                    if !ws.isEmpty {
                        Text("workouts").font(.serif(15)).foregroundStyle(Theme.ink2)
                        ForEach(ws) { w in
                            HStack { Text(w.type.lowercased()); Spacer()
                                Text("\(n(w.minutes)) min" + (w.cals.map { " · \(n($0)) cal" } ?? "")).foregroundStyle(Theme.muted) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 16) {
                    Heading("macros")
                    MacroLine(label: "protein", grams: t.protein, goal: store.proteinGoal, color: Theme.protein)
                    MacroLine(label: "carbs", grams: t.carbs, goal: nil, color: Theme.carbs)
                    MacroLine(label: "fat", grams: t.fat, goal: nil, color: Theme.fat)
                    SyncLine().padding(.top, 10)
                }
                .frame(width: 300)
            }
        }
    }

    var mealGroups: [(String, [Entry])] {
        func meal(_ e: Entry) -> String {
            let h = Calendar.current.component(.hour, from: e.ts)
            switch h { case 4..<11: return "breakfast"; case 11..<16: return "lunch"; case 16..<21: return "dinner"; default: return "late night" }
        }
        let order = ["breakfast", "lunch", "dinner", "late night"]
        let g = Dictionary(grouping: store.today, by: meal)
        return order.compactMap { k in g[k].map { (k, $0) } }
    }
}

struct MacroLine: View {
    let label: String; let grams: Double; let goal: Double?; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).foregroundStyle(Theme.ink)
                Spacer()
                Text(goal.map { "\(n(grams)) / \(n($0)) g" } ?? "\(n(grams)) g").foregroundStyle(Theme.ink2).monospacedDigit()
            }
            if let goal { Bar(fraction: grams / max(goal, 1), color: color) }
        }
    }
}

/// where the watch numbers come from, with sync / import
struct SyncLine: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.lastHealthSync.map { "watch synced \($0.formatted(.relative(presentation: .named)))" } ?? "watch not synced yet")
                .font(.caption).foregroundStyle(Theme.muted)
            HStack(spacing: 14) {
                LinkButton("sync now") { store.syncHealth() }
                LinkButton("import health export") { importing = true }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .xml]) { r in
            if case .success(let url) = r {
                let ok = url.startAccessingSecurityScopedResource()
                store.importHealth(url)
                if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 300) { url.stopAccessingSecurityScopedResource() } }
            }
        }
    }
}

struct EntryRow: View {
    @EnvironmentObject var store: Store
    let e: Entry
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Text(e.name.lowercased() + (e.servings != 1 ? " ×\(n(e.servings, 1))" : "")).foregroundStyle(Theme.ink)
            Text(e.ts.formatted(date: .omitted, time: .shortened).lowercased()).font(.caption).foregroundStyle(Theme.muted)
            Spacer()
            if let p = e.protein { Text("\(n(p))g p").font(.caption).foregroundStyle(Theme.muted) }
            Text(n(e.cals)).monospacedDigit().foregroundStyle(Theme.ink2).frame(width: 48, alignment: .trailing)
            Button { store.remove(e) } label: { Image(systemName: "xmark").font(.caption) }
                .buttonStyle(.borderless).foregroundStyle(Theme.muted).opacity(hover ? 1 : 0)
                .help("remove this entry")
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { Button("Remove", role: .destructive) { store.remove(e) } }
    }
}

// MARK: trends
struct TrendsView: View {
    @EnvironmentObject var store: Store
    @State private var range = Int(ProcessInfo.processInfo.environment["BALANCE_RANGE"] ?? "") ?? 30

    var body: some View {
        let days = store.days(range < 0 ? store.allTimeDays : range)
        let logged = days.compactMap { store.totals[$0] }.filter { $0.cals > 0 }
        let avgIntake = avgOf(logged.map(\.cals))
        let netDays: [(String, Double)] = days.compactMap { d in
            guard let b = store.health[d]?.burned, let e = store.totals[d]?.cals, e > 0, d != store.todayDay else { return nil }
            return (d, e - b)
        }
        let deficit = -netDays.reduce(0) { $0 + $1.1 }
        let hd = days.filter { $0 != store.todayDay }.compactMap { store.health[$0] }
        let watchDays = days.compactMap { store.health[$0] }

        VStack(alignment: .leading, spacing: 34) {
            HStack(alignment: .firstTextBaseline) {
                Text(watchDays.count <= 1 ? "only today so far — import your health export for the full history" : "\(watchDays.count) days of watch data")
                    .font(.callout).foregroundStyle(Theme.muted)
                Spacer()
                RangePicker(range: $range)
            }

            Panel {
                HStack(alignment: .top, spacing: 18) {
                    Figure(label: "avg burned", value: n(avgOf(hd.compactMap(\.burned))), sub: "per day")
                    Figure(label: "avg steps", value: n(avgOf(hd.compactMap(\.steps))))
                    Figure(label: "avg exercise", value: avgOf(hd.compactMap(\.exercise)).map { "\(n($0)) min" } ?? "–")
                    Figure(label: "avg resting hr", value: n(avgOf(hd.compactMap(\.restingHR))), sub: "bpm")
                    Figure(label: "avg intake", value: n(avgIntake), sub: "\(logged.count) days logged")
                    Figure(label: "total deficit", value: netDays.isEmpty ? "–" : n(deficit),
                           sub: netDays.isEmpty ? "needs food + watch" : "≈ \(n(deficit / 3500, 1)) lb", color: deficit >= 0 ? Theme.ink : Theme.over)
                }
            }

            twoUp(MetricChart(title: "calories burned", unit: "cal", color: Theme.burned, days: days) { store.health[$0]?.burned },
                  MetricChart(title: "steps", unit: "steps", color: Theme.sky, days: days) { store.health[$0]?.steps })
            twoUp(MetricChart(title: "calories eaten", unit: "cal", color: Theme.intake, days: days, goal: store.goal) { d in
                      store.totals[d].flatMap { $0.cals > 0 ? $0.cals : nil } },
                  MetricChart(title: "balance (eaten − burned)", unit: "cal", color: Theme.aqua, days: days, signed: true) { d in
                      netDays.first { $0.0 == d }?.1 })
            twoUp(MetricChart(title: "exercise", unit: "min", color: Theme.aqua, days: days) { store.health[$0]?.exercise },
                  MetricChart(title: "resting heart rate", unit: "bpm", color: Theme.over, days: days, line: true) { store.health[$0]?.restingHR })
            MetricChart(title: "workout minutes", unit: "min", color: Theme.yellow, days: days) { d in
                let m = store.workouts.filter { $0.day == d }.reduce(0) { $0 + $1.minutes }
                return m > 0 ? m : nil }
        }
    }

    func twoUp(_ a: MetricChart, _ b: MetricChart) -> some View {
        HStack(alignment: .top, spacing: 18) { a; b }
    }
}

func avgOf(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

// MARK: chart
struct MetricChart: View {
    let title: String; let unit: String; let color: Color; let days: [String]
    var digits = 0
    var line = false
    var goal: Double? = nil
    var signed = false
    var format: ((Double) -> String)? = nil
    let value: (String) -> Double?
    @State private var sel: Date?

    var weekly: Bool { days.count > 120 }
    func label(_ v: Double) -> String { format?(v) ?? (n(v, digits) + (unit.isEmpty ? "" : " \(unit)")) }

    var body: some View {
        let daily = days.compactMap { d in value(d).map { (d, $0) } }
        let avg = avgOf(daily.map(\.1))
        // long ranges: one mark per week (average of the days that have data)
        let pts: [(String, Double)] = weekly ? Dictionary(grouping: daily) { d -> String in
            Day.fmt.string(from: Calendar.current.dateInterval(of: .weekOfYear, for: Day.date(d.0))!.start)
        }.map { ($0.key, $0.value.reduce(0) { $0 + $1.1 } / Double($0.value.count)) }.sorted { $0.0 < $1.0 } : daily
        let unitT: Calendar.Component = weekly ? .weekOfYear : .day

        Panel {
            Heading(title, trailing: avg.map { "avg " + label($0) })
            if pts.isEmpty {
                Text("no data yet").foregroundStyle(Theme.muted).frame(height: 150, alignment: .center).frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(pts, id: \.0) { d, v in
                        if line {
                            LineMark(x: .value("Day", Day.date(d), unit: unitT), y: .value("v", v))
                                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                            PointMark(x: .value("Day", Day.date(d), unit: unitT), y: .value("v", v)).foregroundStyle(color).symbolSize(26)
                        } else {
                            BarMark(x: .value("Day", Day.date(d), unit: unitT), y: .value("v", v), width: .ratio(0.62))
                                .foregroundStyle(signed ? (v <= 0 ? Theme.aqua : Theme.burned) : (goal.map { v > $0 } == true ? Theme.over : color).opacity(0.85))
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        }
                    }
                    if let goal {
                        RuleMark(y: .value("goal", goal)).foregroundStyle(Theme.ink2.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if signed { RuleMark(y: .value("zero", 0)).foregroundStyle(Theme.rule) }
                    if let sel, let hit = pts.first(where: { Calendar.current.isDate(Day.date($0.0), equalTo: sel, toGranularity: unitT) }) {
                        RuleMark(x: .value("Day", Day.date(hit.0), unit: unitT)).foregroundStyle(Theme.rule)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                Tip(lines: [(weekly ? "week of " : "") + Day.date(hit.0).formatted(weekly ? .dateTime.month().day() : .dateTime.weekday().month().day()).lowercased(),
                                            label(hit.1) + (weekly ? " avg" : "")])
                            }
                    }
                }
                .chartXSelection(value: $sel)
                .chartYScale(domain: .automatic(includesZero: !line))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Theme.grid)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(format?(d) ?? n(d)).foregroundStyle(Theme.muted) } }
                    }
                }
                .chartXScale(domain: dayDomain(days))
                .chartXAxis {
                    if weekly {
                        AxisMarks(values: .stride(by: .month, count: max(1, days.count / 180))) { AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(Theme.muted) }
                    } else {
                        AxisMarks(values: .stride(by: .day, count: dayStride(days))) { AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true).foregroundStyle(Theme.muted) }
                    }
                }
                .frame(height: 150)
            }
        }
    }
}

struct Tip: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                Text(l).font(i == 0 ? .caption : .serif(14)).foregroundStyle(i == 0 ? Theme.ink2 : Theme.ink)
            }
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule))
    }
}

// MARK: foods
struct FoodsView: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var sort = [KeyPathComparator(\Item.name)]

    var body: some View {
        let items = store.catalog
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted(using: sort)
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("every food you've logged, one click to log again").font(.callout).foregroundStyle(Theme.muted)
                Spacer()
                TextField("search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            if store.catalog.isEmpty {
                Text("nothing here yet.").foregroundStyle(Theme.muted)
            } else {
                Table(items, sortOrder: $sort) {
                    TableColumn("food", value: \.name) { Text($0.name.lowercased()) }
                    TableColumn("cal", value: \.cals) { Text(n($0.cals)).monospacedDigit() }.width(60)
                    TableColumn("protein", value: \.proteinSort) { Text($0.protein.map { "\(n($0)) g" } ?? "–").monospacedDigit() }.width(70)
                    TableColumn("carbs", value: \.carbsSort) { Text($0.carbs.map { "\(n($0)) g" } ?? "–").monospacedDigit() }.width(60)
                    TableColumn("fat", value: \.fatSort) { Text($0.fat.map { "\(n($0)) g" } ?? "–").monospacedDigit() }.width(60)
                    TableColumn("eaten", value: \.timesEaten) { Text("\($0.timesEaten)×").monospacedDigit() }.width(56)
                    TableColumn("") { i in
                        Button("log") { store.eat(name: i.name, cals: nil, protein: nil, carbs: nil, fat: nil, hall: i.hall, servings: 1) }
                    }.width(50)
                }
                .scrollContentBackground(.hidden)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.rule))
                .frame(minHeight: 460)
            }
        }
    }
}

extension Item {
    var proteinSort: Double { protein ?? -1 }
    var carbsSort: Double { carbs ?? -1 }
    var fatSort: Double { fat ?? -1 }
}

// MARK: history
struct HistoryView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let byDay = Dictionary(grouping: store.allEntries, by: \.day).sorted { $0.key > $1.key }
        VStack(alignment: .leading, spacing: 30) {
            if byDay.isEmpty { Text("nothing logged yet.").foregroundStyle(Theme.muted) }
            ForEach(byDay, id: \.key) { day, entries in
                let total = entries.reduce(0) { $0 + $1.cals }
                let burned = store.health[day]?.burned
                VStack(alignment: .leading, spacing: 8) {
                    Heading(Day.date(day).formatted(.dateTime.weekday(.wide).month().day()).lowercased(),
                            trailing: "\(n(total)) / \(n(store.goal))" + (total > store.goal ? " · over" : "") + (burned.map { " · \(n($0)) burned" } ?? ""))
                    ForEach(entries.sorted { $0.ts < $1.ts }) { EntryRow(e: $0) }.padding(.leading, 21)
                }
            }
        }
    }
}

// MARK: menu bar
struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) var openWindow
    var body: some View {
        let t = store.todayTotal, h = store.todayHealth
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n(abs(store.left))).font(.serif(40)).foregroundStyle(store.left >= 0 ? Theme.ink : Theme.over).monospacedDigit()
                Text(store.left >= 0 ? "left" : "over").font(.serif(17)).foregroundStyle(Theme.ink2)
            }
            Bar(fraction: store.goal > 0 ? store.eaten / store.goal : 0, color: store.left >= 0 ? Theme.sky : Theme.over)
            HStack(spacing: 14) {
                Figure(label: "protein", value: "\(n(t.protein))g")
                Figure(label: "burned", value: n(h?.burned))
                Figure(label: "steps", value: n(h?.steps))
            }
            Rule()
            HStack {
                LinkButton("open balance") {
                    NSApp.setActivationPolicy(.regular)
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                LinkButton("quit") { NSApp.terminate(nil) }
            }
        }
        .padding(18).frame(width: 320).background(Theme.bg)
    }
}

// MARK: snapshot (`Balance --snapshot <dir>` renders the main screens to PNGs and quits)
enum Snapshot {
    @MainActor static func run(_ dir: String) {
        let store = Store()
        let pages: [(String, AnyView)] = [("today", AnyView(TodayView())), ("trends", AnyView(TrendsView()))]
        for (name, v) in pages {
            let r = ImageRenderer(content: v.environmentObject(store).padding(48).frame(width: 1040).background(Theme.bg).environment(\.colorScheme, .light))
            r.scale = 1
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
        exit(0)
    }
}
