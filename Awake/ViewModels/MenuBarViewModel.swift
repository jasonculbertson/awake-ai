import Combine
import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isAwake: Bool = false
    @Published var activeReasons: [ActivationReason] = []
    @Published var timerRemaining: TimeInterval?
    @Published var isAIConfigured: Bool = false

    let powerManager = PowerManager()
    let appMonitor = AppMonitorService()
    let processMonitor = ProcessMonitorService()
    let batteryMonitor = BatteryMonitorService()
    let keychainService = KeychainService()
    let persistence = PersistenceService()
    let launchAtLogin = LaunchAtLoginService()
    let notificationService = NotificationService()
    let hotkeyService = HotkeyService()

    let rulesEngine: RulesEngine
    let aiService: AIService

    private var cancellables = Set<AnyCancellable>()
    private var timerDisplayTimer: Timer?

    init() {
        let aiService = AIService(keychainService: keychainService)
        self.aiService = aiService
        self.rulesEngine = RulesEngine(
            powerManager: powerManager,
            appMonitor: appMonitor,
            processMonitor: processMonitor,
            batteryMonitor: batteryMonitor,
            persistence: persistence,
            notificationService: notificationService
        )

        // Apply saved sleep mode
        powerManager.mode = persistence.sleepPreventionMode

        isAIConfigured = aiService.isConfigured

        setupBindings()
        startServices()
        setupHotkey()

        // Request notification permission
        notificationService.requestPermission()
    }

    private func startServices() {
        appMonitor.startMonitoring()
        batteryMonitor.startMonitoring()

        if persistence.processDetectionEnabled {
            processMonitor.startMonitoring()
        }

        rulesEngine.startEvaluating()

        // Update timer display every second
        timerDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerRemaining = self?.rulesEngine.timerRemaining
            }
        }
    }

    private func setupBindings() {
        rulesEngine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isAwake = state.isActive
                self?.activeReasons = state.reasons
            }
            .store(in: &cancellables)
    }

    private func setupHotkey() {
        hotkeyService.register { [weak self] in
            Task { @MainActor in
                self?.toggleManual()
            }
        }
    }

    func toggleManual() {
        rulesEngine.toggleManual()
    }

    func startTimer(minutes: Int) {
        rulesEngine.startTimer(minutes: minutes)
    }

    func cancelTimer() {
        rulesEngine.cancelTimer()
    }

    func refreshAIStatus() {
        isAIConfigured = aiService.isConfigured
    }

    var statusText: String {
        if !isAwake { return "Sleep allowed" }
        if let reason = activeReasons.first {
            return reason.description
        }
        return "Keeping awake"
    }
}
