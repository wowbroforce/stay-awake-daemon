# stay-awake-daemon

Keeps this Bazzite HTPC/game-mode PC awake while people are actually using it
via **Minecraft** (RCON player count) or **Jellyfin** (active playback), by
holding a `systemd-inhibit` sleep/idle lock while either is true. Solves the
problem of Steam's Game Mode auto-suspend firing off local-input idle time
even though a remote player is connected/streaming.

## How it works

- Polls the local Minecraft server via **RCON** (`list` command) every
  `pollIntervalSeconds` (default 30s) to check for connected players. RCON is
  implemented from scratch over a raw TCP socket (Source RCON protocol) ,
  no external library.
- Polls the local **Jellyfin** `/Sessions` API and checks for any session
  with a non-null `NowPlayingItem` (actual playback, not just an idle
  browser tab left on the library page, `IsActive` is deliberately ignored).
- If either check is true, spawns `systemd-inhibit --what=sleep:idle ... sleep infinity`
  and holds onto that child process; if both go false, kills it, releasing
  the lock. State only changes on transitions, not every poll.

## Requirements

- Minecraft server: `rcon.enabled=true`, `rcon.password=...`, and note
  `rcon.port` (default `25575`) in `server.properties`.
- Jellyfin: an API key from **Dashboard: API Keys**.
- Built binary needs only standard system libs at runtime (glibc, libcurl,
  libssl, libstdc++, etc.), see "Static build" below. No Swift toolchain
  needed on the machine that *runs* it, only to build it.

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

If no config file is found, or it fails to parse, the daemon logs a warning
to stderr and falls back to defaults (RCON/Jellyfin checks will simply fail
until it's fixed, it doesn't crash).

## Build

Swift toolchain is already available on this host via `swiftly`:

```bash
swift build -c release --static-swift-stdlib
```

This statically links the Swift runtime into the binary (confirmed via
`ldd`, no `libswift*.so` dependencies), so the result runs on this host,
or any similar glibc Linux system, without needing Swift installed. The
built binary lands at `.build/release/StayAwakeDaemon`.

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

Also make sure Steam's own Game Mode **Auto-Suspend** timer isn't fighting
this daemon, turn it off (Steam button -> Settings -> Power) so this daemon
is the sole thing deciding whether the machine may sleep.

## Distribution options

The build already produces a single statically-linked binary (no Swift
runtime dependency), which makes it easy to hand off in several ways. None
of these are wired up in this repo yet (no CI, no packaging files), this is
a reference for the tradeoffs if/when it's worth automating.

- **Tarball via GitHub Releases** (simplest, least setup). Build with
  `swift build -c release --static-swift-stdlib`, then archive the binary
  together with `config.example.json` and `stay-awake-daemon.service`:
  ```bash
  tar -czf stay-awake-daemon.tar.gz \
    -C .build/release StayAwakeDaemon \
    config.example.json stay-awake-daemon.service
  ```
  Upload as a release asset. Consumers download, extract, and follow the
  "Deploy as a systemd user service" steps above. No PKGBUILD, formula, or
  Dockerfile to maintain, just a build + upload step, which could later be
  a GitHub Actions job that runs on tag push.

- **One-line install script**. A small `install.sh` (hosted in the repo or a
  release asset) that curls the latest release tarball, extracts the binary
  to `~/.local/bin`, and copies the `.service` file into
  `~/.config/systemd/user/`, i.e. scripting the manual steps above.
  Convenient for the target HTPC, but means telling people to
  `curl | bash`, which is fine for personal use but worth a warning if
  shared more widely.

- **AUR package** (`PKGBUILD`). A natural fit since the dev machine is
  Arch-based (Omarchy); less useful for the actual deploy target
  (Bazzite/Fedora atomic), so only worth it if this ends up running on
  Arch-family boxes too. Would need a `PKGBUILD` that runs `swift build`
  from source (Arch ships a Swift toolchain) or downloads the prebuilt
  binary, plus installing the `.service` file to
  `/usr/lib/systemd/user/`.

- **Homebrew tap** (Linuxbrew). Cross-distro, doesn't require root, and
  Homebrew already knows how to install a systemd user unit via
  `service`/`plist`-style formula hooks (Linux support is less polished
  than macOS's here). Reasonable middle ground between the tarball and a
  full native package, but adds a tap repo to maintain.

- **Nix flake**. Gives a fully reproducible build (pinned Swift toolchain)
  and an installable systemd unit via `nix run`/home-manager module.
  Highest setup cost of these options, but the most reproducible, and a
  good fit if the user ever moves to NixOS.

- **Native distro packages (.rpm/.deb)**. Possible via `fpm` or similar,
  but Bazzite is an immutable/atomic Fedora variant (rpm-ostree) where
  layering RPMs is a heavier operation than dropping a binary in
  `~/.local/bin`, not worth the overhead for a single-user tool like this.

- **Docker/OCI image**. Deliberately not a good fit: the daemon's whole job
  is calling `systemd-inhibit`, which needs the host's systemd/D-Bus user
  session. Running it in a container would mean bind-mounting the host
  session bus and losing most of the isolation benefit anyway, so this
  doesn't earn its complexity here.

Given this is a single-user/single-HTPC tool, the tarball (optionally
wrapped in the install script) covers the actual need; the rest only pay
off if this ever needs to support other machines or other people.

## Known limitations

- RCON response reading assumes a single-packet response, which is correct
  for `list` output on a normal server but wouldn't handle a response
  fragmented across multiple RCON packets (only matters for very long
  command output, not relevant here).
- Config file is plain JSON on disk (not permissions-checked or encrypted),
  so credentials in it are only as safe as normal file permissions make them.
