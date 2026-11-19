# macOS match alerts

Optional menu-bar helper for Chalk Assist. It reads the script’s local match files and displays a floating alert with a chime. Requires macOS 11 or later and the Xcode Command Line Tools to build.

## Build and run

Extract `macos-match-alerts-source.zip`, then open Terminal in the extracted `chalk-match-alerts` folder:

```sh
cd chalk-match-alerts
bash build.sh
open "Chalk Match Alerts.app"
```

The default executor workspace is `~/Opiumware/workspace`. The helper reads `ciu_live_status.json`, `ciu_match_alert.json`, and `ciu_match_alert_settings.json` there. Use the script’s Match Alerts setting to enable or mute alerts. The menu-bar menu includes a test alert and Quit.

For a different workspace, quit any running copy and launch the executable with a process-local override:

```sh
CHALK_EXECUTOR_WORKSPACE="/path/to/executor/workspace" \
  "./Chalk Match Alerts.app/Contents/MacOS/ChalkMatchAlerts"
```

Paths containing spaces are supported. An empty override uses the default workspace.

## Self-test

```sh
"./Chalk Match Alerts.app/Contents/MacOS/ChalkMatchAlerts" --self-test
```

This runs the event-validation and duplicate-alert checks, prints JSON, and exits without opening the app or showing an alert.

To build somewhere else:

```sh
CHALK_ALERTS_OUTPUT_BUNDLE="/tmp/Chalk Match Alerts.app" bash build.sh
```

During normal use, the helper stores preferences through macOS and writes bounded `alert-audit.json` and `helper-status.json` files beside the app. Built apps and these local files are excluded from source control.
