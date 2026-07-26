import Foundation

enum AppConfig {
    private static let plistName = "Config"

    static var supabaseURL: URL {
        guard let urlString = string(for: "SUPABASE_URL"),
              let url = URL(string: urlString),
              !urlString.contains("YOUR_PROJECT")
        else {
            return URL(string: "https://placeholder.supabase.co")!
        }
        return url
    }

    static var supabaseAnonKey: String {
        let key = string(for: "SUPABASE_ANON_KEY") ?? ""
        if key.isEmpty || key.contains("YOUR_ANON_KEY") {
            return "placeholder-anon-key"
        }
        return key
    }

    static var isConfigured: Bool {
        let url = string(for: "SUPABASE_URL") ?? ""
        let key = string(for: "SUPABASE_ANON_KEY") ?? ""
        return !url.contains("YOUR_PROJECT") && !key.contains("YOUR_ANON_KEY") && !url.isEmpty && !key.isEmpty
    }

    private static func string(for key: String) -> String? {
        guard let path = Bundle.main.path(forResource: plistName, ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let value = dict[key] as? String
        else { return nil }
        return value
    }
}
