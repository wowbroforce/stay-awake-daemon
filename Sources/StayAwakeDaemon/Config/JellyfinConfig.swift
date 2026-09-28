import Foundation

struct JellyfinConfig: Decodable {
    var description: String?
    var url: String
    var apiKey: String

    enum CodingKeys: String, CodingKey {
        case description, url, apiKey
    }

    init(description: String? = nil, url: String = "http://127.0.0.1:8096/Sessions", apiKey: String = "CHANGE_ME") {
        self.description = description
        self.url = url
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let defaults = JellyfinConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? defaults.description
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? defaults.url
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
    }

    var resolvedURL: URL {
        guard let resolved = URL(string: url) else {
            fatalError("Invalid jellyfin.url in container: \(url)")
        }
        return resolved
    }

    // Label used in log messages, e.g. " (Living room Jellyfin)" or "" if no description is set.
    var logLabel: String {
        description.map { " (\($0))" } ?? ""
    }
}
