# allincodex

**Use Kiro (or any local OpenAI-compatible gateway) models inside the official Codex Desktop / CLI — in one command, with autostart.**

`allincodex` is a thin, Windows-first orchestrator that wires three pieces together so non-OpenAI models show up natively in the **Codex app model picker**:

```
Codex App / CLI  ──/v1/responses──▶  opencodex proxy (127.0.0.1:10100)
                                          │  Responses ⇄ Chat translation
                                          ▼
                                   Local gateway (e.g. Kiro Gateway, 127.0.0.1:8766/v1)
                                          ▼
                                   Your models (Claude Opus/Sonnet, GLM, MiniMax, …)
```

It does **not** fork or reimplement [opencodex](https://github.com/lidge-jun/opencodex) — it installs and configures it, manages the local gateway lifecycle, sets up logon autostart, and gives you a `doctor` to diagnose the chain.

## TL;DR

```powershell
npm i -g allincodex                  # Windows, Node 18+, PowerShell 7
allincodex init                      # creates %USERPROFILE%\.allincodex\config.json
#   edit that file: point gateway.* at your local OpenAI-compatible gateway, set defaultModel
allincodex setup                     # install opencodex + configure + sync into Codex
allincodex autostart install         # survive reboot (run elevated for the opencodex service)
allincodex doctor                    # verify the chain is healthy
```
Then open Codex → the model picker now lists your gateway's models. Works with **any** OpenAI-compatible gateway (Kiro is the reference); it is not tied to a specific provider.

> Prefer from source? `git clone https://github.com/AgenticLab-SH/allincodex` then run `.\bin\allincodex.ps1 <command>`.

## Why

The Codex Desktop app hides non-OpenAI model slugs behind a server-side allowlist (and on Windows MSIX it rewrites the active model back to a default). `opencodex` works around this by registering its proxy as an OpenAI-authenticated provider (`requires_openai_auth = true`) and injecting a merged OpenAI+custom catalog, so custom models render in the picker. `allincodex` packages that whole setup — plus the gateway it depends on — into one reproducible tool.

## Prerequisites

- Windows 10/11, PowerShell 7 (`pwsh`)
- Node.js 18+ (for `opencodex`)
- A running (or startable) local OpenAI-compatible gateway. Reference: [kiro-gateway](https://github.com/jwadow/kiro-gateway).
- The official **Codex** app/CLI installed and logged in.

## Install

**npm (recommended):**
```powershell
npm i -g allincodex
allincodex init                  # writes %USERPROFILE%\.allincodex\config.json
# edit that config: gateway.wrapperScript, ports, defaultModel
allincodex setup
```

**From source:**
```powershell
git clone https://github.com/AgenticLab-SH/allincodex
cd allincodex
Copy-Item config\allincodex.config.example.json config\allincodex.config.json
# edit the copy
.\bin\allincodex.ps1 setup
```

`setup` installs `@bitkyc08/opencodex` if missing, starts your gateway, writes the opencodex provider config (pointing at the gateway), and syncs models into Codex. Then open Codex and pick a model.

## Commands

| Command | What it does |
|---|---|
| `allincodex init` | Create `~/.allincodex/config.json` from the template (edit it, then setup) |
| `allincodex setup` | Install + configure + sync (run once) |
| `allincodex start` | Bring gateway + proxy up, sync models |
| `allincodex status` / `doctor` | Read-only health of gateway, proxy, Codex injection, autostart |
| `allincodex upstream check` | Check opencodex npm/GitHub and kiro-gateway GitHub, then refresh `TODO.md` |
| `allincodex upstream sync` | Clone/fetch upstream source caches under `.upstream/` for agent review |
| `allincodex update opencodex` | Update the local `ocx` install using opencodex's updater when available |
| `allincodex update kiro-gateway` | Safely fast-forward the local gateway clone only when it has no dirty changes |
| `allincodex autostart install` | Logon autostart: gateway (Startup launcher) + opencodex service |
| `allincodex autostart uninstall` | Remove the gateway logon launcher |
| `allincodex restore` | Stop proxy + gateway, restore vanilla Codex (`ocx stop`) |
| `allincodex about` | Show version, watermark, and authorship commitment |
| `allincodex verify-author "<phrase>"` | Prove original authorship against the published commitment |

## Autostart (survive reboot)

```powershell
.\bin\allincodex.ps1 autostart install
```

- Gateway: a hidden logon launcher in your Startup folder (no admin).
- opencodex: registers its background service (`ocx service install`) — **run from an elevated PowerShell** the first time (Task Scheduler registration needs admin).

Both layers are idempotent and self-healing (opencodex auto-restarts on crash; the gateway launcher only starts it if down).

## Security

- **No secrets are stored in this repo or written by allincodex.** The gateway API key is read at runtime from your gateway's private env file (`PROXY_API_KEY`) or an environment variable (`apiKeyEnvVar`), and passed to opencodex via `apiKeyEnv` — never written into a config file in plaintext.
- The proxy binds to loopback (`127.0.0.1`) only. Do not expose it to a network without an auth token.

## How it works

`allincodex` writes `~/.opencodex/config.json` with your gateway as an `openai-chat` provider (key by env reference) and uses the current opencodex lifecycle commands (`ocx ensure`, then `ocx sync-cache` when available; legacy installs fall back to `ocx start` + `ocx sync`). This injects into `~/.codex/config.toml`:
`model_provider = "opencodex"`, a merged model catalog, and `requires_openai_auth = true` so the Codex picker shows the models. The default model stays a recognized slug so the app does not reset it.

## Upstream watch

Because [opencodex](https://github.com/lidge-jun/opencodex) and [kiro-gateway](https://github.com/jwadow/kiro-gateway) move quickly, this repo includes a project-local watch list:

```powershell
allincodex upstream check        # network read; updates TODO.md
allincodex upstream check --json # machine-readable for agents
allincodex upstream sync         # downloads/fetches source caches under .upstream/
allincodex update kiro-gateway   # refuses to pull if local gateway files are dirty
```

Future Codex/Claude agents should read `AGENTS.md`, run the check, and use `TODO.md` as the local follow-up surface before changing integration code.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). Quick check: `allincodex doctor`.

## Credits

- [opencodex](https://github.com/lidge-jun/opencodex) by lidge-jun — the proxy that does the Responses⇄provider translation and Codex injection.
- [kiro-gateway](https://github.com/jwadow/kiro-gateway) — reference local OpenAI-compatible gateway.

## Authorship & provenance

`allincodex` is original work by **AgenticLab-SH**. It is MIT-licensed (fork freely), but authorship is marked and **provable**:

- Watermark `AIC✦SH✦2026` in `NOTICE`, every script header, and a hidden HTML comment in this README.
- Functional mark: `allincodex about` prints the watermark + commitment.
- **Cryptographic commitment**: `NOTICE` and `lib/common.ps1` publish `sha256(secret phrase)`. The phrase is never stored in the repo. The original author can prove authorship at any time — even against a fork that strips the visible marks — without revealing the secret:

  ```powershell
  allincodex verify-author "<phrase>"   # prints "AUTHOR VERIFIED" only for the genuine phrase
  ```

Honest note: in any open-source project the in-file marks *can* be edited out of a copy. What cannot be forged is (a) producing the secret phrase behind the published commitment, and (b) this repository's public git history (the original-author commit on the upstream remote) — together they are durable proof of original authorship.

## Disclaimer (UAYOR)

`allincodex` is an independent, community tool and is **not affiliated with or endorsed by OpenAI, Anthropic, AWS/Kiro, or any provider**. Routing provider traffic through unofficial proxies may violate a provider's Terms of Service and can result in account action. **Review each provider's ToS and use at your own risk.** The authors accept no liability.

## License

MIT — see [LICENSE](LICENSE).


<!--
  ┌────────────────────────────────────────────────────────────┐
  │  allincodex — original work by AgenticLab-SH (2026)          │
  │  hidden authorship watermark: AIC✦SH✦2026                    │
  │  if you forked this, this line is your tell. say hi 👋        │
  └────────────────────────────────────────────────────────────┘
-->
