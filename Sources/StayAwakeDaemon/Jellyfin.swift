import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Jellyfin check

func jellyfinIsPlaying(_ jellyfin: JellyfinConfig) -> Bool {
    guard let url = jellyfin.resolvedURL else {
        logError("Jellyfin check skipped\(jellyfin.logLabel): invalid url \"\(jellyfin.url)\"")
        return false
    }
    var request = URLRequest(url: url)
    request.setValue(jellyfin.apiKey, forHTTPHeaderField: "X-Emby-Token")
    request.timeoutInterval = 5

    let semaphore = DispatchSemaphore(value: 0)
    // Safe: semaphore.wait() below happens-after the closure's semaphore.signal(),
    // so there's no actual concurrent access despite the compiler's caution here.
    nonisolated(unsafe) var isPlaying = false

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        guard let data = data, error == nil else {
            logError("Jellyfin check failed\(jellyfin.logLabel): \(error?.localizedDescription ?? "unknown error")")
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let hint = (status == 401 || status == 403) ? " (check jellyfin.apiKey)" : ""
            logError("Jellyfin check failed\(jellyfin.logLabel): HTTP \(status)\(hint)")
            return
        }
        guard let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logError("Jellyfin check failed\(jellyfin.logLabel): response is not a JSON array of sessions (is jellyfin.url the /Sessions endpoint?)")
            return
        }
        isPlaying = sessions.contains { session in
            guard let nowPlaying = session["NowPlayingItem"] else { return false }
            return !(nowPlaying is NSNull)
        }
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 10)
    return isPlaying
}
