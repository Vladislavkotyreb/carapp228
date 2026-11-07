import AuthenticationServices
import Foundation
import Security
import SwiftData

@MainActor
final class AppState: ObservableObject {
    private let onboardingKey = "hasCompletedOnboarding"
    private var pendingState: String?
    private var account: LocalAppleAccount?

    @Published private(set) var isSignedIn = false
    @Published private(set) var isCheckingAccount = true
    @Published var accountError: String?
    @Published var accountDeleted = false
    @Published private(set) var isDeletingAccount = false
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        account = try? AppleAccountKeychain.load()
        #if DEBUG
        if UITestLaunch.isActive {
            isSignedIn = ProcessInfo.processInfo.arguments.contains("-beepy-test-authenticated")
            isCheckingAccount = false
        }
        #endif
    }

    var hasLocalAccount: Bool { account != nil }

    func completeOnboarding() { hasCompletedOnboarding = true }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        accountError = nil
        let state = UUID().uuidString
        pendingState = state
        request.state = state
        // Для локального входа достаточно стабильного идентификатора Apple.
        request.requestedScopes = []
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        defer { pendingState = nil }
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let pendingState, credential.state == pendingState,
                  !credential.user.isEmpty else {
                accountError = "Не удалось подтвердить вход. Попробуйте ещё раз."
                return
            }
            do {
                account = try AppleAccountKeychain.load()
            } catch {
                accountError = "Связка ключей недоступна. Разблокируйте iPhone и повторите вход."
                return
            }
            // Чужой Apple ID не получает доступ к базе предыдущего владельца.
            guard account == nil || account?.userID == credential.user else {
                accountError = "Эти данные связаны с другим Apple ID. Войдите с прежним аккаунтом или удалите локальные данные."
                return
            }
            let signedIn = LocalAppleAccount(userID: credential.user, active: true)
            do {
                try AppleAccountKeychain.save(signedIn)
                account = signedIn
                isSignedIn = true
            } catch {
                accountError = "Не удалось сохранить вход на устройстве. Попробуйте ещё раз."
            }
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            accountError = "Не удалось войти через Apple. Проверьте соединение и попробуйте ещё раз."
        }
    }

    func checkAppleAccount() async {
        #if DEBUG
        if UITestLaunch.isActive { return }
        #endif
        defer { isCheckingAccount = false }
        guard let saved = account, saved.active else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: saved.userID)
            // За время запроса человек мог выйти или удалить аккаунт.
            guard account?.userID == saved.userID, account?.active == true else { return }
            if state == .authorized {
                isSignedIn = true
            } else {
                signOut()
            }
        } catch {
            // Уже открытый сеанс сохраняется при временной сетевой ошибке.
            if !isSignedIn { accountError = "Не удалось проверить Apple ID. Повторите вход." }
        }
    }

    func signOut() {
        // Отозванный доступ блокирует экран даже при ошибке записи Keychain.
        isSignedIn = false
        stopTracking()
        guard var saved = account else { return }
        saved.active = false
        account = saved
        do {
            try AppleAccountKeychain.save(saved)
        } catch {
            accountError = "Не удалось сохранить выход на устройстве. Повторите попытку."
        }
    }

    func deleteLocalAccount(in context: ModelContext) async {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            if TripSync.shared.hasAccount { try await TripSync.shared.deleteFromServer() }
            stopTracking()
            let trips = try context.fetch(FetchDescriptor<Trip>())
            let cars = try context.fetch(FetchDescriptor<Car>())
            let snapshotKeys = trips.map(\.snapshotKey)
            let carIDs = cars.map { ServiceReminder.key(createdAt: $0.createdAt) }
            try context.transaction {
                try context.delete(model: Trip.self)
                try context.delete(model: EngineFinding.self)
                try context.delete(model: EngineCheck.self)
                try context.delete(model: ServiceWorkItem.self)
                try context.delete(model: ServiceRecord.self)
                try context.delete(model: Car.self)
                try context.delete(model: Place.self)
                try context.save()
            }
            snapshotKeys.forEach { TripSnapshots.remove(for: $0) }
            carIDs.forEach { ServiceReminder.forget(id: $0) }
            try TripTracker.shared.clearLocalHistory()
            try AppleAccountKeychain.remove()
            account = nil
            isSignedIn = false
            hasCompletedOnboarding = false
            UserDefaults.standard.removeObject(forKey: TripCar.key)
            accountDeleted = true
        } catch {
            accountError = "Не удалось завершить удаление. Повторите попытку."
        }
    }

    private func stopTracking() {
        TripTracker.shared.setAuto(false)
        UserDefaults.standard.set(false, forKey: LocationSwitch.key)
        TripTracker.shared.locationSwitched()
    }
}

private struct LocalAppleAccount: Codable {
    let userID: String
    var active: Bool
}

private enum AppleAccountKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.vladislavkotyrev.appmvp.apple-account",
        kSecAttrAccount as String: "local-account",
    ]

    static func load() throws -> LocalAppleAccount? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainFailure() }
        return try JSONDecoder().decode(LocalAppleAccount.self, from: data)
    }

    static func save(_ account: LocalAppleAccount) throws {
        let data = try JSONEncoder().encode(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainFailure() }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeychainFailure() }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure() }
    }

    private struct KeychainFailure: Error {}
}
