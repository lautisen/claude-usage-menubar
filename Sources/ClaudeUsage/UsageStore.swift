import Foundation
import ServiceManagement

@MainActor
final class UsageStore: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var plan: String?
    @Published var lastUpdated: Date?
    @Published var error: String?
    @Published var isLoading = false
    @Published var nextRefresh: Date?

    /// Se llama cada vez que cambian los datos, para redibujar el icono de la barra.
    var onChange: (() -> Void)?

    private var timer: Timer?
    private let fetcher: () async throws -> (UsageResponse, Credentials)
    static let refreshInterval: TimeInterval = 120

    init(fetcher: @escaping () async throws -> (UsageResponse, Credentials) = { try await UsageService.fetch() }) {
        self.fetcher = fetcher
    }

    var sessionPercent: Double? { usage?.fiveHour?.utilization }

    func start() {
        refresh()
        scheduleTimer()
    }

    /// Reinicia el temporizador tras cada actualización (automática o manual) para que la
    /// cuenta atrás hasta la siguiente sea siempre exacta.
    private func scheduleTimer() {
        timer?.invalidate()
        nextRefresh = Date().addingTimeInterval(Self.refreshInterval)
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Refresca al abrir el desplegable, salvo que los datos sean muy recientes.
    func refreshIfStale() {
        if isStale() { refresh() }
    }

    func isStale(now: Date = Date()) -> Bool {
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) >= 30
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task { await performRefresh() }
    }

    func performRefresh() async {
        isLoading = true
        do {
            let (response, creds) = try await fetcher()
            usage = response
            plan = creds.subscriptionType
            lastUpdated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        scheduleTimer()
        onChange?()
    }

    // MARK: Abrir al iniciar sesión

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
