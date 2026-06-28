#!/usr/bin/env node
// allincodex npm launcher -> forwards to the PowerShell CLI.
// authorship watermark: AIC✦SH✦2026 — original work by AgenticLab-SH
"use strict";
const { spawnSync } = require("child_process");
const path = require("path");

if (process.platform !== "win32") {
  console.error(
    "allincodex currently supports Windows only (PowerShell 7 + Codex Desktop).\n" +
    "Follow along / contribute cross-platform support: https://github.com/AgenticLab-SH/allincodex"
  );
  process.exit(1);
}

const ps1 = path.join(__dirname, "allincodex.ps1");
const args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, ...process.argv.slice(2)];

let r = spawnSync("pwsh", args, { stdio: "inherit" });
if (r.error) {
  // pwsh (PowerShell 7) not found -> fall back to Windows PowerShell 5.1
  r = spawnSync("powershell", args, { stdio: "inherit" });
}
if (r.error) {
  console.error("allincodex: could not launch PowerShell (pwsh / powershell). Install PowerShell 7.");
  process.exit(1);
}
process.exit(r.status === null ? 1 : r.status);
