// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import AppKit
import Charts
import SwiftUI

@MainActor
enum HistoryWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryView()))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.setContentSize(NSSize(width: 680, height: 560))
            window.center()
            self.window = window
        }
        window?.title = L("Nabız · Geçmiş", "Nabız · History")
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// CPU, RAM, GPU and the main AI limit, all in the accent (orange and red stay for warnings), over the last hour, day or week.
struct HistoryView: View {
    enum Span: String, CaseIterable, Identifiable {
        case hour, day, week
        var id: String { rawValue }

        var seconds: TimeInterval {
            switch self {
            case .hour: 3600
            case .day: 86_400
            case .week: 7 * 86_400
            }
        }

        /// Points per chart: one a minute for the hour, every 5 minutes for the day, every 30 for the week.
        var buckets: Int {
            switch self {
            case .hour: 60
            case .day: 288
            case .week: 336
            }
        }

        var title: String {
            switch self {
            case .hour: L("1 saat", "1 hour")
            case .day: L("24 saat", "24 hours")
            case .week: L("7 gün", "7 days")
            }
        }
    }

    @State private var span: Span = .day
    @AppStorage(Prefs.language) private var language = "system"
    private let history = UsageHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack {
                Text(L("Geçmiş", "History")).font(Theme.title).foregroundStyle(Theme.text)
                Spacer()
                Picker("", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: Theme.Spacing.l) {
                    chart(L("İşlemci", "CPU"), .cpu, Theme.accent, now: context.date)
                    chart(L("Bellek", "Memory"), .memory, Theme.accent, now: context.date)
                    chart(L("Grafik", "GPU"), .gpu, Theme.accent, now: context.date)
                    if !history.points(.ai, span: span.seconds, buckets: span.buckets, now: context.date).isEmpty {
                        chart(L("AI limiti (kullanılan)", "AI limit (used)"), .ai, Theme.accent, now: context.date)
                    }
                }
            }
            Text(L("Dakikada bir ölçülür, son 7 gün Mac'inde saklanır. Boş aralıklar Mac'in uykuda olduğu zamanlardır.",
                   "Measured every minute and kept on your Mac for 7 days. Gaps are when the Mac was asleep."))
                .font(Theme.small).foregroundStyle(Theme.textMuted)
        }
        .padding(Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.l)
        .frame(minWidth: 560, minHeight: 480)
        .background(MenuMaterial().ignoresSafeArea())
        .appearanceRoot(opaqueFill: Theme.surface)
    }

    private func chart(_ title: String, _ series: UsageHistory.Series, _ color: Color, now: Date) -> some View {
        let points = history.points(series, span: span.seconds, buckets: span.buckets, now: now)
        let average = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
        let peak = points.map(\.value).max()
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title).font(Theme.bodyStrong).foregroundStyle(Theme.text)
                Spacer()
                if let average, let peak {
                    Text(L("ort. \(Format.percent(average / 100)) · en yüksek \(Format.percent(peak / 100))",
                           "avg \(Format.percent(average / 100)) · peak \(Format.percent(peak / 100))"))
                        .font(Theme.small).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
            }
            if points.isEmpty {
                Text(L("Henüz veri yok; birkaç dakika içinde dolmaya başlar.", "No data yet; it fills in within a few minutes."))
                    .font(Theme.small).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: Theme.historyChart, alignment: .center)
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("t", point.date), y: .value("%", point.value), series: .value("s", point.segment),
                             stacking: .unstacked)
                        .foregroundStyle(color.opacity(0.18))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", point.date), y: .value("%", point.value), series: .value("s", point.segment))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0)%").font(Theme.small) }
                    }
                }
                // Aligned labels keep the last one inside the chart instead of cut at the edge.
                .chartXAxis { AxisMarks(preset: .aligned) }
                .chartXScale(domain: now.addingTimeInterval(-span.seconds)...now)
                .frame(height: Theme.historyChart)
            }
        }
    }
}
