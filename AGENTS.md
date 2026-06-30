# allincodex Agent Notes

This repo wires Codex, opencodex, and local OpenAI-compatible gateways. Work from
current evidence, because both opencodex and kiro-gateway are moving quickly.

## Startup Checks

Run these before making integration changes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\bin\allincodex.ps1 doctor
pwsh -NoProfile -ExecutionPolicy Bypass -File .\bin\allincodex.ps1 upstream check
```

Use `upstream check --json` when another agent needs machine-readable evidence.
The command refreshes the generated block in `TODO.md`.

## Upstream Sources

- opencodex: npm package `@bitkyc08/opencodex`, repo `https://github.com/lidge-jun/opencodex`
- kiro-gateway: repo `https://github.com/jwadow/kiro-gateway`

Use this command to download or refresh source caches under `.upstream/`:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\bin\allincodex.ps1 upstream sync
```

Do not commit secrets, logs, browser profiles, or gateway private env files.
Preserve local changes under `C:\Users\kshcg\agent-hub\tools\gateways\kiro-gateway`
unless the user explicitly asks to reset or overwrite them.

## Update Rules

- Prefer opencodex's current CLI surface (`ocx ensure`, `ocx sync-cache`,
  `ocx codex-shim`, `ocx update`) when available.
- If `ocx --version` is behind npm latest, record it in `TODO.md`; update with
  `allincodex update opencodex` only when the task calls for changing the local
  install.
- If kiro-gateway remote HEAD differs from the local clone, inspect local dirty
  files before pulling. `allincodex update kiro-gateway` will refuse to pull
  while the clone is dirty.

## Verification

For code changes, run:

```powershell
npm test
pwsh -NoProfile -ExecutionPolicy Bypass -File .\bin\allincodex.ps1 upstream check --json
```
