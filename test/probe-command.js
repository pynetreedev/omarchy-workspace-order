// Mirror of probeCommand() from Workspaces.qml, extracted so the exact argv the
// widget builds can be asserted without a running Quickshell or systemd. If you
// change probeCommand in the QML, mirror the change here.
//
// Params stand in for the QML `root.*` properties the real function reads.
export function probeCommand(target, { probeTimeoutMs, maxOutputBytes, hyprSignature }) {
  if (target !== "workspaces" && target !== "monitors")
    return [];

  var cmd = ["systemd-run", "--user", "--pipe", "--quiet", "--collect",
             "-p", "RuntimeMaxSec=" + String(Math.max(1, Math.ceil(probeTimeoutMs / 1000))),
             "-p", "KillSignal=SIGKILL",
             "-p", "LogLevelMax=notice"];

  if (/^[0-9A-Za-z_]+$/.test(hyprSignature))
    cmd.push("-p", "Environment=HYPRLAND_INSTANCE_SIGNATURE=" + hyprSignature);

  cmd.push("--", "sh", "-c", "hyprctl -j " + target + " | head -c " + maxOutputBytes);
  return cmd;
}
