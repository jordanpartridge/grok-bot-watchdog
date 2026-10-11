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
- Often happens after a compositor restart, a suspend/resume, or when the
  app was started from a shell that lacked the graphical session's env
  (`WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, ...).

## How it works (Linux)

`grok-bot-ensure` runs every 5 minutes from a systemd **user** timer:

1. Locates the app binary (`/opt/Grok Bot/grok-bot` or `GBW_APP_BIN`).
2. Health check:
   - main process = the app binary without a Chromium `--type=` flag;
   - daemon = a `node.mojom.NodeService` utility child of the main process
     (current builds), or any process matching `GBW_DAEMON_MATCH`
     (default `local-exec-daemon`, for builds that run it standalone).
   - Healthy -> exit 0. **It never restarts anything while healthy.**
3. Unhealthy -> guards, in order: pause file, debounce (2 consecutive bad
   checks by default), game guard (skips restarting a running app while a
   Steam game / gamescope / SteamVR is active), relaunch cap (3 per hour).
4. Discovers the session without hardcoding: borrows env from a live
   compositor/app process in `/proc`, then fills gaps from sockets in
   `/run/user/$UID` (`hypr/*/.socket.sock`, `wayland-*`, `bus`),
   `/tmp/.X11-unix`, and `loginctl` (Hyprland, GNOME, KDE, sway, X11).
5. Pushes that env into `systemctl --user` / dbus activation env, then
   tier 1: graceful stop (SIGTERM, wait) and relaunch in its own scope;
   tier 2: SIGKILL the whole app tree and relaunch.

Exit codes: `0` ok, `10` recovered, `11` deferred, `12` dry-run would act,
`2` usage, `3` no session, `4` app not found, `5` failed, `6` locked.

Safe over SSH, idempotent (flock + debounce), no root.

```sh
grok-bot-ensure --check      # report only
grok-bot-ensure --dry-run    # show what it would do
grok-bot-ensure --force      # skip debounce/game/cap guards
touch ~/.local/state/grok-bot-watchdog/PAUSE   # pause the watchdog
```

Optional config: `~/.config/grok-bot-watchdog/config` (see
`linux/config.example`). If another tool already relaunches the app when it
is closed, set `GBW_RELAUNCH_IF_MAIN_DOWN=0`, and point `GBW_LAUNCH_CMD` at
your compositor's launcher if you want the app to start in its usual place.

## Install

```sh
git clone https://github.com/OWNER/grok-bot-watchdog && cd grok-bot-watchdog
./linux/install.sh            # copies to ~/.local/bin, enables the timer
systemctl --user list-timers grok-bot-watchdog.timer
journalctl --user -u grok-bot-watchdog.service -n 20
```

macOS (**untested**): `./macos/install.sh` installs a LaunchAgent that runs
`grok-bot-ensure-macos` every 300 s (uses `pgrep`, `osascript` quit and
`open -a`).

## Uninstall

```sh
./linux/install.sh --uninstall
./macos/install.sh --uninstall   # macOS
```

## Limitations

- Daemon detection is a heuristic based on process layout; an app update
  can change it. The daemon could also be alive but wedged (not detected).
- The daemon lives inside the app, so recovery restarts the whole app.
- The game guard is pattern-based (`GBW_GAME_PROCS`, `GBW_GAME_MATCH`); it errs on the side
  of not restarting.
- Only the user's own session; multi-seat setups are not handled.
- The macOS version has not been tested on real hardware.

## License

MIT
