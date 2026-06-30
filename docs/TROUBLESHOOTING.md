# Troubleshooting

Run `allincodex doctor` first — it reports the health of each layer.

Also run `allincodex upstream check` when behavior differs from these docs.
`opencodex` changes quickly; current versions provide `ocx ensure`,
`ocx sync-cache`, `ocx codex-shim`, and `ocx update`.

## Models don't appear in the Codex app picker
- Ensure `ocx sync` ran (it injects the merged catalog). `allincodex start` does this.
- On current opencodex versions, `allincodex start` prefers `ocx ensure` and
  `ocx sync-cache`. If those commands are missing, update opencodex or use the
  legacy `ocx start` / `ocx sync` path.
- The default model in `~/.codex/config.toml` must be a recognized slug (e.g. `gpt-5.5`) so MSIX Codex doesn't reset it. opencodex sets this; don't override with an unknown slug.
- Fully close and reopen Codex so it reloads config on startup (the catalog is read at launch).

## A model is selected but returns nothing / errors
- `allincodex doctor` — is the gateway (8766) up? Is the proxy (10100) up?
- Gateway down: `allincodex start` (or your gateway's own start command).
- Check the upstream login (e.g. `kiro-cli whoami`). An expired gateway login means the proxy is up but the model 401s upstream.

## After reboot, kiro models stop working
- The gateway has no boot autostart by default. Run `allincodex autostart install`.
- opencodex needs its service registered once from an elevated shell: `ocx service install`.

## Codex app looks broken / empty after switching
- This usually means a custom catalog was injected without the opencodex `requires_openai_auth` provider, OR the proxy was unreachable. Use `allincodex restore` to return to vanilla Codex, then `allincodex setup` again with the proxy healthy.

## Do NOT
- Do not kill processes by runtime name (e.g. `Stop-Process -Name bun`/`node`) — those runtimes are shared by other tools/agents and you will kill unrelated sessions. Target the specific port owner (10100 / 8766) or use `ocx`/gateway commands.

## Restore everything to vanilla
```powershell
allincodex restore        # ocx stop + gateway stop
# or fully remove opencodex:
ocx uninstall
allincodex autostart uninstall
```
