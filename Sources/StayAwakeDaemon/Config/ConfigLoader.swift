import Foundation

// Resolution order for the config file path:
// 1. First CLI argument, if given.
// 2. $STAY_AWAKE_CONFIG, if set.
// 3. $XDG_CONFIG_HOME/stay-awake-daemon/config.json, or ~/.config/stay-awake-daemon/config.json.
func configFilePath() -> String {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    if let envPath = ProcessInfo.processInfo.environment["STAY_AWAKE_CONFIG"] {
        return envPath
    }
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
    return "\(xdgConfig)/stay-awake-daemon/config.json"
}

func loadConfig() -> AppConfig {
    let path = configFilePath()
    guard let data = FileManager.default.contents(atPath: path) else {
        logError("No config file found at \(path) - falling back to defaults (no minecraft/jellyfin sections; see README).")
        return AppConfig()
    }
    do {
        return try JSONDecoder().decode(AppConfig.self, from: data)
    } catch {
        logError("Failed to parse config file at \(path): \(error) - falling back to defaults.")
        return AppConfig()
    }
}
