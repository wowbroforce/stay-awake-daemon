import Foundation

struct AppConfig: Decodable {
    var pollIntervalSeconds: UInt32
    var minecraft: MinecraftConfig?
    var jellyfin: JellyfinConfig?

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
        pollIntervalSeconds = try c.decodeIfPresent(UInt32.self, forKey: .pollIntervalSeconds) ?? 30
        minecraft = try c.decodeIfPresent(MinecraftConfig.self, forKey: .minecraft)
        jellyfin = try c.decodeIfPresent(JellyfinConfig.self, forKey: .jellyfin)
    }
}
