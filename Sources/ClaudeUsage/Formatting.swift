import Foundation

/// Nivel de uso de una ventana, usado para colorear barras y porcentajes.
enum UsageLevel: Equatable {
    case low, medium, high

    init(percent: Double) {
        switch percent {
        case ..<50: self = .low
        case ..<80: self = .medium
        default: self = .high
        }
    }
}

/// Aviso en la barra de menús: solo se colorea cuando el uso de la sesión empieza a ser alto;
/// si no, el icono se ve como uno de sistema.
enum MenuBarAlert: Equatable {
    case none, warning, critical

    init(percent: Double?) {
        switch percent ?? 0 {
        case 90...: self = .critical
        case 75...: self = .warning
        default: self = .none
        }
    }
}

func formatCountdown(to date: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(date.timeIntervalSince(now)))
    let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
    if days > 0 { return "\(days) d \(hours) h" }
    if hours > 0 { return "\(hours) h \(minutes) min" }
    return "\(minutes) min"
}

func formatResetTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_ES")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE d, HH:mm"
    return formatter.string(from: date)
}

/// Texto junto al icono de la barra de menús, p. ej. " 42% · 2h13m".
func menuBarTitle(sessionPercent: Double?, reset: Date?, now: Date = Date()) -> String {
    var title = " " + (sessionPercent.map { "\(Int($0.rounded()))%" } ?? "–")
    if let reset, reset > now {
        title += " · " + formatCountdown(to: reset, now: now)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "min", with: "m")
    }
    return title
}

/// La API devuelve microsegundos ("…00.456921+00:00"), que ISO8601DateFormatter no acepta:
/// se recortan las fracciones antes de parsear.
func parseISODate(_ string: String) -> Date? {
    let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: trimmed)
}
