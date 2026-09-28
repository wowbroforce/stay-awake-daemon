import Foundation

// Sleep inhibitor

final class SleepInhibitor {
    private var process: Process?

    func setActive(_ active: Bool) {
        if active && process == nil {
            log("Activity detected -> taking sleep inhibitor lock")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/systemd-inhibit")
            p.arguments = [
                "--what=sleep:idle",
                "--who=stay-awake-daemon",
                "--why=Minecraft players or Jellyfin playback active",
                "--mode=block",
                "sleep", "infinity",
            ]
            do {
                try p.run()
                process = p
            } catch {
                logError("Failed to start systemd-inhibit: \(error)")
            }
        } else if !active, let p = process {
            log("No activity -> releasing sleep inhibitor lock")
            p.terminate()
            p.waitUntilExit()
            process = nil
        }
    }
}
