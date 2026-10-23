import Foundation
import Security

/// Сервер Beepy (`server/`): адрес и токен установки.
///
/// Адрес — из Info.plist (`BeepyServerURL`) в выпуске; в отладке — ещё из
/// окружения запуска (`BEEPY_SERVER_URL`), а в симуляторе по умолчанию —
/// локальный сервер на маке. На телефоне `127.0.0.1` — сам телефон, поэтому
/// там адрес задаётся явно. Нет адреса — сервера нет.
enum BeepyServer {
    static var url: URL? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let value = env["BEEPY_SERVER_URL"] ?? env["BEEPY_SYNC_URL"], let url = URL(string: value) {
            return url
        }
        #endif
        if let value = Bundle.main.object(forInfoDictionaryKey: "BeepyServerURL") as? String,
           !value.isEmpty, let url = URL(string: value) {
            return url
        }
        #if DEBUG && targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8787")
        #else
        return nil
        #endif
    }

    /// Токен установки для поиска по госномеру: случайный, без согласия и
    /// без персональных данных — по нему сервер считает лимиты. Заводится
    /// при первом поиске.
    static func installToken(base: URL, renew: Bool = false) async throws -> String {
        if !renew, let token = InstallKeychain.token { return token }
        var request = URLRequest(url: base.appending(path: "/v1/installs"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 201,
              let reply = try? JSONDecoder().decode(InstallReply.self, from: data) else {
            throw VehicleLookupError.unavailable
        }
        InstallKeychain.token = reply.token
        return reply.token
    }

    /// POST с токеном установки. Токен отозван или база сервера новая —
    /// одна попытка с новым токеном.
    static func post<Body: Encodable>(_ path: String, _ body: Body) async throws -> (Data, Int) {
        guard let base = url else { throw VehicleLookupError.unavailable }
        for attempt in 0..<2 {
            let token = try await installToken(base: base, renew: attempt > 0)
            var request = URLRequest(url: base.appending(path: path))
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(body)
            guard let (data, response) = try? await session.data(for: request) else {
                throw VehicleLookupError.unavailable
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401, attempt == 0 { continue }
            return (data, code)
        }
        throw VehicleLookupError.unavailable
    }

    /// Эфемерная сессия: госномер и VIN — персональные данные, дисковому
    /// кэшу их не отдаём.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private struct InstallReply: Decodable { let token: String }
}

/// Токен установки — в Связке ключей только этого телефона: лимиты
/// считаются на установку, переносить его на другой телефон незачем.
private enum InstallKeychain {
    private static let service = "com.vladislavkotyrev.appmvp.install"
    private static let account = "install-token"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(match as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var item = match
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
