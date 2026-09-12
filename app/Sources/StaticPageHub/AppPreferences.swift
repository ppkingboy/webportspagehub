import Foundation

enum AppPreferences {
    private static let defaults = UserDefaults.standard

    static var port: Int {
        get {
            let value = defaults.integer(forKey: "serverPort")
            return value > 0 ? value : 8000
        }
        set {
            defaults.set(newValue, forKey: "serverPort")
        }
    }

    static var binding: ServerBinding {
        get {
            let value = defaults.string(forKey: "serverBinding") ?? ""
            return ServerBinding(rawValue: value) ?? .lan
        }
        set {
            defaults.set(newValue.rawValue, forKey: "serverBinding")
        }
    }

    static var selectedAddress: String {
        get {
            defaults.string(forKey: "selectedAddress") ?? ""
        }
        set {
            defaults.set(newValue, forKey: "selectedAddress")
        }
    }

    static var autoStart: Bool {
        get {
            defaults.bool(forKey: "autoStartServer")
        }
        set {
            defaults.set(newValue, forKey: "autoStartServer")
        }
    }
}
