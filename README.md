# stay-awake-daemon

Keeps this Bazzite HTPC/game-mode PC awake while people are actually using it
via **Minecraft** (RCON player count) or **Jellyfin** (active playback), by
holding a `systemd-inhibit` sleep/idle lock while either is true. Solves the
problem of Steam's Game Mode auto-suspend firing off local-input idle time
even though a remote player is connected/streaming.

## How it works

- Polls the local Minecraft server via **RCON** (`list` command) every
  `pollIntervalSeconds` (default 30s) to check for connected players. RCON is
  implemented from scratch over a raw TCP socket (Source RCON protocol),
  no external library.
- Polls the local **Jellyfin** `/Sessions` API and checks for any session
  with a non-null `NowPlayingItem` (actual playback, not just an idle
  browser tab left on the library page, `IsActive` is deliberately ignored).
- If either check is true, spawns `systemd-inhibit --what=sleep:idle ... sleep infinity`
  and holds onto that child process; if both go false, kills it, releasing
  the lock. State only changes on transitions, not every poll.
- On `SIGTERM`/`SIGINT` the current poll finishes, the inhibitor lock is
  released explicitly, and the daemon exits, so stopping the service never
  leaves a stray lock (or a stray `sleep infinity`) behind.

## Requirements

- Minecraft server: `rcon.enabled=true`, `rcon.password=...`, and note
  `rcon.port` (default `25575`) in `server.properties`.
- Jellyfin: an API key from **Dashboard: API Keys**.
- `systemd-inhibit` at `/usr/bin/systemd-inhibit`, and a systemd user
  session/D-Bus to take the lock against.
- No Swift toolchain on the machine that *runs* the daemon, only to build
  it. The fully static build (see "Build") has no runtime library
  dependencies at all; the default build needs the usual system libs
  (glibc, libcurl, libssl, libstdc++).

## Usage

```
stay-awake-daemon [config-path] [--help|-h]
```

`--help` prints the full config reference (every field, its type and its
default) and exits; it is generated from the same defaults the daemon uses,
so it is always in sync with the binary you are holding.

## Configuration

Configured via a JSON file, read at startup, no rebuild needed to change
credentials. Copy the example and edit it:

```bash
mkdir -p ~/.config/stay-awake-daemon
cp config.example.json ~/.config/stay-awake-daemon/config.json
$EDITOR ~/.config/stay-awake-daemon/config.json
```

```json
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
```

The `minecraft` and `jellyfin` sections are each entirely optional -
if a section is missing, that check is skipped entirely (not just left on
defaults that would fail). For example, on a machine with no Minecraft
server, just omit the `minecraft` section:

```json
{
  "jellyfin": {
    "url": "http://127.0.0.1:8096/Sessions",
    "apiKey": "CHANGE_ME"
  }
}
```

Fields within a present section fall back to the values shown above if
omitted. `description` is an optional free-text label for a section (e.g.
"Living room server") that gets included in that check's error log
messages, purely for identification - it has no effect on behavior.
`pollIntervalSeconds` is top-level and always defaults to 30. The
daemon looks for the config file in this order:

1. First command-line argument, if given (`stay-awake-daemon /path/to/config.json`).
2. `$STAY_AWAKE_CONFIG`, if set.
3. `$XDG_CONFIG_HOME/stay-awake-daemon/config.json`, or
   `~/.config/stay-awake-daemon/config.json` if `XDG_CONFIG_HOME` isn't set.

If no config file is found, or it fails to parse, the daemon logs the reason
to stderr and continues with no sections configured. In that state it has
nothing to monitor, so it logs that too and idles forever without ever
inhibiting sleep - it does not crash, and it does not silently hold the
machine awake.

## Install from a release

The one-line installer downloads a release tarball, verifies its
`.sha256` if one is published, installs the binary to `~/.local/bin`, the
systemd user unit to `~/.config/systemd/user/`, and seeds
`~/.config/stay-awake-daemon/config.json` from the example if you don't
already have one:

```bash
curl -fsSL https://raw.githubusercontent.com/wowbroforce/stay-awake-daemon/main/install.sh | bash
```

It deliberately does not enable the service, start it, or touch
`loginctl`; it prints those steps instead (see "Deploy as a systemd user
service"). Pass a tag to pin a version, either as an argument or via
`$STAY_AWAKE_VERSION`; with neither, it resolves the latest GitHub release:

```bash
curl -fsSL .../install.sh | bash -s -- v0.1.0-alpha
```

The script expects the release asset to be named
`stay-awake-daemon-<tag>-linux-x86_64.tar.gz`, containing `StayAwakeDaemon`,
`config.example.json` and `stay-awake-daemon.service` at the archive root.

## Build

Swift toolchain is available on this host via `swiftly`. Two builds are
supported; both produce a single self-contained binary, neither needs Swift
on the target machine.

**Default (glibc, portable within the distro family):**

```bash
swift build -c release --static-swift-stdlib
```

This statically links the Swift runtime (confirmed via `ldd`, no
`libswift*.so` dependencies) but still links the usual system libraries
dynamically (glibc, libcurl, libssl, libstdc++, libgcc). The binary lands
at `.build/release/StayAwakeDaemon` and runs on this host or a similar
glibc Linux system.

**Fully static (musl, portable anywhere x86_64 Linux):**

```bash
swift build -c release --swift-sdk x86_64-swift-linux-musl
```

This needs the Swift static Linux SDK installed once, matching the
toolchain in use (`swift-6.3-RELEASE_static-linux-0.1.0` here; check with
`swift sdk list`). Install it with
`swift sdk install <url> --checksum <sha256>`, taking both values from the
"Static Linux SDK" download on <https://www.swift.org/install/linux/>,
since the checksum changes per release.

The static SDK links musl and everything else in: `ldd` reports "not a
dynamic executable", so the result runs on any x86_64 Linux regardless of
glibc version. This is what the deploy target
(Bazzite, an atomic Fedora variant) wants. The binary lands at
`.build/x86_64-swift-linux-musl/release/StayAwakeDaemon` and is large
because it is unstripped; `strip` cuts it from roughly 158M to 62M and is
worth doing before packaging a release.

Supporting the static SDK is why `Sources/StayAwakeDaemon/PlatformLibc.swift`
exists: the platform libc module is `Glibc` in the default build and `Musl`
in the static one, so the socket calls in `RCONClient` go through thin
`sys*` wrappers instead of module-qualified names.

## Deploy as a systemd user service

```bash
mkdir -p ~/.local/bin ~/.config/systemd/user
cp .build/release/StayAwakeDaemon ~/.local/bin/stay-awake-daemon
cp stay-awake-daemon.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now stay-awake-daemon.service
```

This is a systemd **user** unit, so by default it only runs while you have
an active login session, and stops when you log out. Since this is an HTPC
meant to sit there unattended, enable **lingering** so your user's systemd
instance (and this service) starts at boot and keeps running with no one
logged in:

```bash
loginctl enable-linger "$USER"
```

Check it's running / see logs:

```bash
systemctl --user status stay-awake-daemon.service
journalctl --user -u stay-awake-daemon.service -f
```

## Distribution options

The build produces a single self-contained binary, which makes it easy to
hand off. Both steps below are in place: `install.sh` is in the repo and
releases are built by hand. There is still no CI, so tagging, building and
uploading a release is a manual step.

- **Tarball via GitHub Releases** (simplest, least setup). Build, then
  archive the binary together with `config.example.json` and
  `stay-awake-daemon.service`:
  ```bash
  tar -czf stay-awake-daemon-v0.1.1-alpha-linux-x86_64.tar.gz \
    -C .build/x86_64-swift-linux-musl/release StayAwakeDaemon \
    -C "$OLDPWD" config.example.json stay-awake-daemon.service
  sha256sum stay-awake-daemon-v0.1.1-alpha-linux-x86_64.tar.gz \
    > stay-awake-daemon-v0.1.1-alpha-linux-x86_64.tar.gz.sha256
  ```
  Upload both as release assets. Consumers run `install.sh`, or extract and
  follow the "Deploy as a systemd user service" steps above. Just a build +
  upload step, which could later be a GitHub Actions job that runs on tag
  push. Local release artifacts live in `dist/`, which is gitignored.

- **One-line install script**. `install.sh` in the repo root, run via
  `curl | bash` as shown under "Install from a release". Convenient for the
  target HTPC, but means telling people to `curl | bash`, which is fine for
  personal use but worth a warning if shared more widely.

## Known limitations

- RCON response reading assumes a single-packet response, which is correct
  for `list` output on a normal server but wouldn't handle a response
  fragmented across multiple RCON packets (only matters for very long
  command output, not relevant here).
- The player count is parsed out of the English vanilla `list` wording
  ("There are N of a max of M players online"). A server (or plugin) that
  rewords or localizes that reply reads as zero players.
- RCON connects by IP only (`inet_pton`), so `minecraft.host` must be a
  literal IPv4 address, not a hostname like `localhost`.
- Paused Jellyfin playback still counts as activity, since a paused session
  keeps a non-null `NowPlayingItem`. That is usually what you want on an
  HTPC (nobody wants the machine to suspend during a pause), but it means a
  session left paused overnight holds the lock until the client disconnects.
- Each poll is synchronous and the checks run one after another, so a
  network stall can stretch a cycle by up to the RCON (5s) and Jellyfin
  (10s) timeouts before the next sleep begins.
- Config file is plain JSON on disk (not permissions-checked or encrypted),
  so credentials in it are only as safe as normal file permissions make them.
