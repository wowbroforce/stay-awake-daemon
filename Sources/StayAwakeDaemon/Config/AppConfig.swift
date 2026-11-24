import Foundation

struct AppConfig: Decodable {
    var pollIntervalSeconds: UInt32
    var minecraft: MinecraftConfig?
    var jellyfin: JellyfinConfig?

    static let minPollIntervalSeconds: UInt32 = 1

    enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds, minecraft, jellyfin
    }

    init() {
        pollIntervalSeconds = 30
        minecraft = nil
        jellyfin = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let interval = try c.decodeIfPresent(UInt32.self, forKey: .pollIntervalSeconds) ?? 30
        if interval < AppConfig.minPollIntervalSeconds {
            logError("pollIntervalSeconds \(interval) is below the minimum; using \(AppConfig.minPollIntervalSeconds).")
        }
        pollIntervalSeconds = max(interval, AppConfig.minPollIntervalSeconds)
        minecraft = try c.decodeIfPresent(MinecraftConfig.self, forKey: .minecraft)
        jellyfin = try c.decodeIfPresent(JellyfinConfig.self, forKey: .jellyfin)
    }
}
