# Beacon

Dead-simple remote access to **your own** Windows PC, using the Slack you
already use as the wire. Outbound HTTPS only — no firewall changes, no inbound
ports, no VPN. One file. It just works.

> **Only install this on machines you own.** Beacon runs commands as the
> logged-in Windows user. That is the entire point — and the entire risk.
> Never install it anywhere you don't have the owner's explicit permission.

## Download

Get **`Beacon.ps1`** from the latest release:

**https://github.com/jessestay/beacon/releases**

(One file. That's the whole product.)

## Install — 3 steps, ~3 minutes

1. Save `Beacon.ps1` anywhere on the PC (Desktop is fine).
2. Open PowerShell and run:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   cd $HOME\Desktop
   .\Beacon.ps1 -SelfTest
   ```
   Expect a list of `PASS` lines ending in `SELF-TEST: all passed.`
   This changes nothing — it just proves the script works on your machine.
3. Then:
   ```powershell
   .\Beacon.ps1 -Install
   ```
   It asks **one question** — the Slack bot ID allowed to send commands
   (find it in the bot's Slack profile; it looks like `B0C39F2CNHJ`).
   Then it diagnoses the machine, repairs what it can, installs itself as a
   logon task, and starts. You'll see `[beacon] alive` in your Slack channel
   within a minute or two.

## Using it

From then on, post this **as the authorized bot** in your channel:

```
[beacon-cmd:1] Get-Date
```

Beacon runs it (60-second timeout, output truncated to 8KB) and replies
in-thread:

```
[beacon-result:1]
```powershell
<output>
```
```

Heartbeats (`[beacon] alive — …`) post every 10 minutes so you always know
it's watching.

## What it does on install

1. **Diagnose** (read-only): Tailscale state, the desktop agent task,
   port 8099, Ollama models, MACF team processes, Anthropic key presence.
2. **Repair** (idempotent): restarts the agent task if the port is closed,
   starts `ollama serve` if Ollama is installed but not serving.
3. **Beacon loop**: polls Slack every 30s for `[beacon-cmd:<id>]` messages.

## Commands

| | |
|---|---|
| `.\Beacon.ps1 -SelfTest` | Acceptance tests. Changes nothing, posts nothing. |
| `.\Beacon.ps1 -Install` | Diagnose → repair → install logon task → start. |
| `.\Beacon.ps1 -Uninstall` | Remove the task. A task-started loop exits on its own. |
| `.\Beacon.ps1 -NoLoop` | Diagnose + repair only. |

## Tests

`Beacon.Tests.ps1` is the Pester v5 suite — the TDD contract every change
must satisfy. CI runs it on a Windows runner:

```powershell
Invoke-Pester ./Beacon.Tests.ps1
```

The philosophy: **tests first, "it just works" always.** Zero config, every
behavior has a working default, every remote call has a timeout, output never
floods the channel, diagnose is read-only, repair is idempotent.

## Trust model (v0.1.0)

- Commands execute **only** from messages posted by the bot ID **you**
  configure at install. Humans, other bots, and lookalike text are ignored.
- Commands run as the logged-in Windows user — your machine, your call.
- The Slack token is auto-discovered from the local MACF `slack-agents/.env`
  if present; otherwise Beacon asks once. When installed, it's stored in
  `$HOME\Beacon\.token`, ACL'd to your Windows user only.
- No secrets are ever posted to Slack. Nothing leaves the machine except
  command output addressed to your own channel.

## For maintainers (MACF team)

When the desktop MACF team is back online, the **CTO** owns this repo:
harden the trust model (per-command allowlist, signed commands), keep the
Pester suite green, and keep the "it just works" bar for every change.
v0.1.0 is the working bootstrap.
