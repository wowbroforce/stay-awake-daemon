#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif

// Set by the signal handler; checked in the poll loop. A plain top-level Int32
// write/read is the conventional sig_atomic_t-equivalent here (single word,
// no allocation), which is all that's safe to do from a signal handler.
var terminationRequested: Int32 = 0

func handleTerminationSignal(_ sig: Int32) {
    terminationRequested = 1
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    printHelp()
    exit(0)
}

// Install before starting the loop so a signal delivered early (or during
// the first poll) is still caught rather than falling back to the default
// terminate-immediately disposition.
signal(SIGTERM, handleTerminationSignal)
signal(SIGINT, handleTerminationSignal)
signal(SIGPIPE, SIG_IGN)

let config = loadConfig()
let inhibitor = SleepInhibitor()

if config.minecraft == nil && config.jellyfin == nil {
    logError("No minecraft or jellyfin section configured - nothing to monitor; see --help.")
}

while terminationRequested == 0 {
    let mcActive = config.minecraft.map(minecraftHasPlayers) ?? false
    let jellyfinActive = config.jellyfin.map(jellyfinIsPlaying) ?? false
    inhibitor.setActive(mcActive || jellyfinActive)
    sleep(config.pollIntervalSeconds)
}

log("Received termination signal -> releasing sleep inhibitor lock before exiting")
inhibitor.setActive(false)
