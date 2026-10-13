import SwiftUI

func usageColor(_ percent: Double) -> Color {
    switch percent {
    case ..<50: return .green
    case ..<80: return .orange
    default: return .red
    }
}

func formatCountdown(to date: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
    if days > 0 { return "\(days) d \(hours) h" }
    if hours > 0 { return "\(hours) h \(minutes) min" }
    return "\(minutes) min"
}

func formatResetTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_ES")
    formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE d, HH:mm"
    return formatter.string(from: date)
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let usage = store.usage {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        if let w = usage.fiveHour {
                            LimitCard(title: "Sesión actual", subtitle: "Ventana de 5 horas",
                                      window: w, now: context.date, prominent: true)
                        }
                        if let w = usage.sevenDay {
                            LimitCard(title: "Semanal", subtitle: "Todos los modelos", window: w, now: context.date)
                        }
                        if let w = usage.sevenDayOpus, w.utilization != nil {
                            LimitCard(title: "Semanal · Opus", subtitle: nil, window: w, now: context.date)
                        }
                        if let w = usage.sevenDaySonnet, w.utilization != nil {
                            LimitCard(title: "Semanal · Sonnet", subtitle: nil, window: w, now: context.date)
                        }
                    }
                }
                if let rows = usage.sevenDayBreakdown?.rows, !rows.isEmpty {
                    BreakdownView(rows: rows)
                }
                if let extra = usage.extraUsage, extra.isEnabled == true {
                    ExtraUsageView(extra: extra)
                }
            } else if store.error == nil {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .padding(.vertical, 30)
            }

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Uso de Claude").font(.headline)
            if let plan = store.plan {
                Text(plan.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            }
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.borderless)
            .help("Actualizar")
        }
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 1) {
                    if let last = store.lastUpdated {
                        Text("Actualizado \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                            .environment(\.locale, Locale(identifier: "es_ES"))
                    }
                    if store.isLoading {
                        Text("Actualizando…")
                    } else if let next = store.nextRefresh {
                        let secs = max(0, Int(next.timeIntervalSince(context.date)))
                        Text("Próxima en \(secs / 60):\(String(format: "%02d", secs % 60))").monospacedDigit()
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("Al iniciar", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                .toggleStyle(.checkbox)
                .font(.caption)
            Button("Salir") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}

struct LimitCard: View {
    let title: String
    let subtitle: String?
    let window: UsageWindow
    let now: Date
    var prominent = false

    var body: some View {
        let percent = window.utilization ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(prominent ? .subheadline.weight(.semibold) : .subheadline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text("\(Int(percent.rounded()))%")
                    .font(prominent ? .system(size: 28, weight: .bold, design: .rounded) : .title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(usageColor(percent))
            }
            UsageBar(percent: percent, height: prominent ? 10 : 6)
            if let reset = window.resetDate {
                Text(reset > now
                     ? "Se reinicia en \(formatCountdown(to: reset, now: now)) · \(formatResetTime(reset))"
                     : "Reiniciado — pendiente de actualizar")
                    .font(.caption).foregroundStyle(.secondary)
            } else if percent == 0 {
                Text("Sin uso en esta ventana").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(prominent ? 12 : 0)
        .background {
            if prominent { RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)) }
        }
    }
}

struct UsageBar: View {
    let percent: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(usageColor(percent))
                    .frame(width: max(height, geo.size.width * min(percent, 100) / 100))
                    .opacity(percent > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

struct BreakdownView: View {
    let rows: [BreakdownRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reparto del uso semanal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(rows.sorted { $0.percent > $1.percent }) { row in
                HStack(spacing: 8) {
                    Text(row.displayName).font(.caption).frame(width: 84, alignment: .leading)
                    UsageBar(percent: row.percent, height: 4).tint(.accentColor)
                    Text("\(Int(row.percent))%").font(.caption).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

struct ExtraUsageView: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Uso extra").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                    Text(String(format: "%.2f / %.2f %@", used, limit, extra.currency ?? ""))
                        .font(.caption).monospacedDigit()
                }
            }
            if let u = extra.utilization { UsageBar(percent: u, height: 4) }
        }
    }
}
