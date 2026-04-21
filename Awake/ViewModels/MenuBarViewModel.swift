import Combine
import Foundation

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isAwake: Bool = false
    @Published var activeReasons: [ActivationReason] = []
    @Published var timerRemaining: TimeInterval?
    @Published var isAIConfigured: Bool = false
    @Published var showOnboarding: Bool = false

    let powerManager = PowerManager()
    let appMonitor = AppMonitorService()
    let processMonitor = ProcessMonitorService()
    let batteryMonitor = BatteryMonitorService()
    let keychainService = KeychainService()
    let persistence = PersistenceService()
    let launchAtLogin = LaunchAtLoginService()
    let notificationService = NotificationService()
    let hotkeyService = HotkeyService()
    let wifiMonitor: WiFiMonitorService
    let cpuMonitor: CPUMonitorService

    let rulesEngine: RulesEngine
    let aiService: AIService
    let storeKit = StoreKitService()

    private var cancellables = Set<AnyCancellable>()
    private var timerDisplayTimer: Timer?

    init() {
        let aiService = AIService(keychainService: keychainService)
        self.aiService = aiService

        let wifi = WiFiMonitorService()
        let cpu = CPUMonitorService()
        self.wifiMonitor = wifi
        self.cpuMonitor = cpu

        self.rulesEngine = RulesEngine(
            powerManager: powerManager,
            appMonitor: appMonitor,
            processMonitor: processMonitor,
            batteryMonitor: batteryMonitor,
            persistence: persistence,
            notificationService: notificationService,
            wifiMonitor: wifi,
            cpuMonitor: cpu
        )

        // Apply saved sleep mode
        powerManager.mode = persistence.sleepPreventionMode

        isAIConfigured = aiService.isConfigured

        // Show onboarding on first launch
        showOnboarding = !persistence.hasCompletedOnboarding

        setupBindings()
        startServices()
        setupHotkey()

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
        let displayTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerRemaining = self?.rulesEngine.timerRemaining
            }
        }
        RunLoop.main.add(displayTimer, forMode: .common)
        timerDisplayTimer = displayTimer
    }

    private func setupBindings() {
        rulesEngine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isAwake = state.isActive
                self?.activeReasons = state.reasons
            }
            .store(in: &cancellables)

        batteryMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func setupHotkey() {
        hotkeyService.register { [weak self] in
            Task { @MainActor in
                self?.toggleManual()
            }
        }
    }

    func completeOnboarding() {
        persistence.hasCompletedOnboarding = true
        showOnboarding = false
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

    func stopAllSessions() {
        rulesEngine.clearAllRules()
        for i in rulesEngine.watchList.indices {
            rulesEngine.watchList[i].isEnabled = false
        }
        persistence.saveWatchList(rulesEngine.watchList)
        rulesEngine.updateWatchList(rulesEngine.watchList)
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
