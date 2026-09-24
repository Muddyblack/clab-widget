// Quickshell entry point. Lives at the repo root because Quickshell sandboxes
// QML to the entry file's directory, and hyprland/ must reach the shared
// components under package/contents/. Run with `qs -p <repo>`.
import "hyprland"

ClabShell {}
