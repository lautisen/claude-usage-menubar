import Foundation

// MARK: - Modelo de la respuesta de /api/oauth/usage

struct UsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    var resetDate: Date? { resetsAt.flatMap(parseISODate) }
}

struct BreakdownRow: Decodable, Identifiable {
    let key: String
    let displayName: String
    let percent: Double
    var id: String { key }
}

struct Breakdown: Decodable {
    let rows: [BreakdownRow]
}

struct ExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?
}

struct UsageResponse: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUsage: ExtraUsage?
    let sevenDayBreakdown: Breakdown?
}

struct Credentials {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?
}

enum UsageError: LocalizedError {
    case noCredentials
    case tokenExpired
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "No encuentro las credenciales de Claude Code. Inicia sesión con `claude`."
        case .tokenExpired: return "El token ha caducado. Abre Claude Code para que lo renueve."
        case .rateLimited: return "Demasiadas peticiones, reintento en breve."
        case .http(let code): return "Error del servidor (HTTP \(code))."
        }
    }
}

// MARK: - Servicio

enum UsageService {
    /// Lee el token OAuth que Claude Code guarda en el Llavero. Se usa /usr/bin/security
    /// porque ya tiene acceso al ítem y así la app no dispara diálogos de permisos.
    static func readCredentials() throws -> Credentials {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw UsageError.noCredentials }

        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(accessToken: token, expiresAt: expires,
                           subscriptionType: oauth["subscriptionType"] as? String)
    }

    static func fetch() async throws -> (UsageResponse, Credentials) {
        let creds = try readCredentials()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        case 401, 403: throw UsageError.tokenExpired
        case 429: throw UsageError.rateLimited
        default: throw UsageError.http(status)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try decoder.decode(UsageResponse.self, from: data), creds)
    }
}

/// La API devuelve microsegundos ("…00.456921+00:00"), que ISO8601DateFormatter no acepta:
/// se recortan las fracciones antes de parsear.
func parseISODate(_ string: String) -> Date? {
    let trimmed = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: trimmed)
}
