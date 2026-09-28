import Foundation

struct MinecraftConfig: Decodable {
    var description: String?
    var host: String
    var port: UInt16
    var password: String

    enum CodingKeys: String, CodingKey {
        case description, host, port, password
    }

    init(description: String? = nil, host: String = "127.0.0.1", port: UInt16 = 25575, password: String = "CHANGE_ME") {
        self.description = description
        self.host = host
        self.port = port
        self.password = password
    }

    init(from decoder: Decoder) throws {
        let defaults = MinecraftConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? defaults.description
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? defaults.host
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? defaults.port
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? defaults.password
    }

    // Label used in log messages, e.g. " (Living room server)" or "" if no description is set.
    var logLabel: String {
        description.map { " (\($0))" } ?? ""
    }
}
