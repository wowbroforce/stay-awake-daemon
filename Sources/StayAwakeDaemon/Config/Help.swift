import Foundation

func printHelp() {
    let defaultInterval = AppConfig().pollIntervalSeconds
    let mcDefaults = MinecraftConfig()
    let jfDefaults = JellyfinConfig()
    let programName = CommandLine.arguments.first ?? "stay-awake-daemon"
    print("""
    Usage: \(programName) [config-path] [--help|-h]

    Keeps the machine awake (via systemd-inhibit) while Minecraft has
    connected players or Jellyfin has an active playback session. Polls
    both every pollIntervalSeconds and holds/releases the inhibitor lock
    on transitions.

    Config file path resolution (first match wins):
      1. [config-path] argument above, if given.
      2. $STAY_AWAKE_CONFIG environment variable, if set.
      3. $XDG_CONFIG_HOME/stay-awake-daemon/config.json, falling back to
         ~/.config/stay-awake-daemon/config.json.

    If no config file is found, or it fails to parse, the daemon logs a
    warning to stderr and runs with no sections configured (it will idle
    forever without inhibiting sleep - it will not crash).

    The config is split into a "minecraft" section and a "jellyfin"
    section, each entirely optional. Only sections that are present are
    checked - omit a section entirely to disable that check rather than
    leaving it pointed at defaults that will just fail.

    Top-level fields:
      pollIntervalSeconds  UInt32  seconds between checks  (default: \(defaultInterval))

    "minecraft" section fields (all optional if the section is present):
      description  String  Label used in log messages  (default: none)
      host         String  Minecraft RCON host         (default: "\(mcDefaults.host)")
      port         UInt16  Minecraft RCON port          (default: \(mcDefaults.port))
      password     String  Minecraft RCON password      (default: "\(mcDefaults.password)")

    "jellyfin" section fields (all optional if the section is present):
      description  String  Label used in log messages   (default: none)
      url          String  Jellyfin /Sessions endpoint  (default: "\(jfDefaults.url)")
      apiKey       String  Jellyfin API key             (default: "\(jfDefaults.apiKey)")

    Example config file (both sections enabled):
      {
        "pollIntervalSeconds": 30,
        "minecraft": {
          "description": "Living room server",
          "host": "127.0.0.1",
          "port": 25575,
          "password": "CHANGE_ME"
        },
        "jellyfin": {
          "description": "Living room Jellyfin",
          "url": "http://127.0.0.1:8096/Sessions",
          "apiKey": "CHANGE_ME"
        }
      }

    Example config file (Jellyfin only - Minecraft check disabled):
      {
        "jellyfin": {
          "url": "http://127.0.0.1:8096/Sessions",
          "apiKey": "CHANGE_ME"
        }
      }

    Requirements:
      - Minecraft server.properties: rcon.enabled=true, rcon.password set,
        matching rcon.port.
      - Jellyfin API key from Dashboard -> API Keys.
      - Runs as a systemd (user) service; see stay-awake-daemon.service.
    """)
}
