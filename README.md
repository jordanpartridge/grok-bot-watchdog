# grok-bot-watchdog

A small watchdog that notices when the Grok Bot desktop app's **local-exec
daemon** has dropped and brings it back.

> Community-made. Not affiliated with, endorsed by, or supported by the
> vendor of Grok Bot. Use at your own risk.

## Symptoms

- The desktop app shows as disconnected for local execution, and remote
  commands to the machine fail or time out.
- The app window may still be open, but the background Node service that
  runs local commands has exited.
- Often follows a compositor restart, suspend/resume, or starting the app
  from a shell that lacked the graphical session's environment.

## How it works (Linux)

`grok-bot-ensure` runs every 5 minutes from a systemd **user** timer.

1. **Find the app**: `/opt/Grok Bot/grok-bot` or `GBW_APP_BIN`. Processes
   are matched by owner and their real executable (`/proc/PID/exe`; inside
   the hardened unit, where that link is unreadable, the command line must
   start with the exact app path), never by a command-line substring, so an editor or pager showing the path never counts.
2. **Health check**: main process = app executable without a Chromium
   `--type=` flag. The daemon is the specific `node.mojom.NodeService`
   child that carries a local-exec marker: it has child processes (the
   shells it runs) or holds a terminal-output file open
   (`GBW_DAEMON_FD_MARKER`). For builds that run a standalone daemon, set
   `GBW_DAEMON_MATCH`.
   - marker found -> **healthy, nothing is touched**; the number of
     NodeService children is remembered as a baseline together with the
     main PID and its start time (`/proc/PID/stat` field 22);
   - no marker but no NodeService child lost since the baseline ->
     `ok_idle`, nothing is touched (an idle daemon has no marker);
   - fewer NodeService children than the baseline **of the same app
     instance** (PID and start time match) -> daemon down. A baseline from
     an earlier instance is ignored.
   - after a relaunch, a new main process whose NodeService children reach
     the previous count counts as recovered (the fresh daemon is idle).
3. **Guards** before any action: pause files, debounce (2 bad checks),
   game guard (gamescope / SteamVR / a Steam game launched via `reaper`),
   stream guard (Sunshine running, its log written since Sunshine started,
   and the last client event in it is a connect; or an established peer on
   the stream ports), exponential backoff (300 s, doubling), and a cap of
   3 relaunches per hour with a desktop notification when it is hit. If a
   guard holds off a needed relaunch for more than 30 min
   (`GBW_BLOCK_NOTIFY`), you get one notification. A relaunch is counted
   toward the cap only when a launch is actually attempted. The
   game/stream guard is re-checked right before the graceful stop, before
   the tier-2 SIGKILL, and before every launch.
4. **App not running**: left alone by default (`GBW_RELAUNCH_IF_MAIN_DOWN=0`).
   When enabled, a clean quit (Electron removed its `SingletonLock`) is
   still respected.
5. **Session discovery** without hardcoding: environment of a live
   compositor/app process, then sockets under `/run/user/$UID`
   (`hypr/*/.socket.sock`, `wayland-*`, `bus`), `/tmp/.X11-unix`, and
   `loginctl` (Hyprland, GNOME, KDE, sway, X11).
6. **Recovery**: push the session env into the user manager; tier 1 =
   SIGTERM, wait, relaunch; tier 2 = SIGKILL the app tree, relaunch. The app
   is started with `systemd-run --user` (or `GBW_LAUNCH_CMD`), so it never
   inherits the watchdog's sandbox and outlives it. Without a reachable
   user manager the script falls back to `setsid`, but **refuses** that when
   `INVOCATION_ID` is set (it is running inside a systemd unit, whose
   read-only sandbox the app would inherit); set `GBW_LAUNCH_CMD` instead.

### Exit codes

| code | meaning |
|-----:|---------|
| 0  | healthy / idle, nothing done |
| 10 | was unhealthy, recovered |
| 11 | unhealthy but deferred (paused, debounce, game, stream, backoff, cap, clean exit, app-down disabled) |
| 12 | `--dry-run`: would have acted |
| 2  | usage or config error |
| 3  | no graphical session found |
| 4  | app binary not found |
| 5  | relaunch attempted, still unhealthy |
| 6  | another run holds the lock |
| 7  | hostname does not match `GBW_HOST_REGEX` |

`--check` is report-only: `0` healthy (or paused), `1` not healthy
(codes 2-7 still apply for errors). The service treats 10 and 11 as success.

```sh
grok-bot-ensure --check      # report only
grok-bot-ensure --dry-run    # show what it would do
grok-bot-ensure --force      # skip debounce/backoff/cap (guards still apply)
touch ~/.config/grok-bot-watchdog/PAUSE   # pause (any file in GBW_PAUSE_FILES)
```

Configuration: `~/.config/grok-bot-watchdog/config` (installed from
`linux/config.example`; every setting is documented there).

## Install

```sh
git clone https://github.com/jordanpartridge/grok-bot-watchdog && cd grok-bot-watchdog
./linux/install.sh
systemctl --user list-timers grok-bot-watchdog.timer
journalctl --user -u grok-bot-watchdog.service -n 20
```

The service runs with `NoNewPrivileges`, `ProtectSystem=strict` (write
access only to its state dir), `ProtectKernelTunables` and
`RestrictSUIDSGID`. Previous script versions are kept under
`~/.local/state/grok-bot-watchdog/previous/`, not next to your files.

macOS (**untested**): `./macos/install.sh` installs a LaunchAgent running
`grok-bot-ensure-macos` every 300 s (pgrep/lsof detection, `open -g -a`,
same guards, cap and backoff; logs in `~/Library/Logs/grok-bot-watchdog`).
It restarts the app when the daemon drops (same marker + per-instance
baseline logic), and starts a missing app only when opted in. Its game
guard also covers Steam games (`steamapps/common`), Wine/CrossOver/Whisky
and common launchers; the Sunshine log is `~/.config/sunshine/sunshine.log`
on macOS as well.

## Uninstall

```sh
./linux/install.sh --uninstall   # keep config and state
./linux/install.sh --purge       # also delete config and state
./macos/install.sh --uninstall | --purge
```

## Limitations

- Daemon detection is a heuristic based on process layout; an app update
  can change it. A daemon that is alive but wedged is not detected.
- An idle daemon with no marker is only declared down if the app loses a
  NodeService child compared with the last positive identification.
- The daemon lives inside the app, so recovery restarts the whole app.
- Game/stream guards are pattern-based and err on the side of not acting.
- Inside the hardened unit (systemd puts it in a user namespace),
  `/proc/PID/exe`, `/proc/PID/fd/*` links and `/proc/PID/environ` of the
  app may be unreadable. Fallbacks: the app is identified by a command line
  that starts with the exact app path; the daemon by its child processes
  (the open-file marker is then skipped) and the per-instance NodeService
  baseline; session variables come from compositor sockets under
  `/run/user/$UID`, `/tmp/.X11-unix` and `loginctl` instead of a donor
  process's environment. Run `grok-bot-ensure -v` outside the unit to see
  every signal.
- Single-user, single-session only. The macOS version is untested.

## License

MIT
