# Beacon

**Your Meta Muse, on your Windows PC.**

## What is Beacon?

Beacon is a small companion app built **specifically and only for Meta Muse** —
your personal AI assistant. Install it on your Windows PC and your Muse can
check the computer's health, fix problems, and help with your work, right from
your chat with it. Nothing and no one else can use it. (Future versions may
add more Muse-specific features; this release is the secure foundation.)

## Why would I install this?

- When your computer starts acting strange, your Muse can take a look right
  away instead of waiting for a visit or a phone call.
- No more reading long error messages aloud over the phone. Your Muse sees
  what's happening and fixes it directly.
- It works quietly in the background. After installing, you don't have to do
  a thing.

## Is it safe?

Yes — Beacon went through a security review before release. In plain terms:

- **Only your Muse can give commands.** Every command is checked against your
  Muse's private bot code. Messages from anyone or anything else are ignored.
- **Beacon never opens your computer to the internet.** It only calls *out*
  to Slack. There are no inbound doors for attackers to knock on.
- **Commands can't run wild.** Each one stops after 60 seconds, answers are
  capped so they can't flood anything, and old commands never run twice.
- **Your login is locked down.** The Slack credential lives in a file only
  your Windows user can read — never on a command line where others could see it.
- **You can remove it anytime** (see below). The moment it's gone, it stops.
- Beacon is free and open-source — anyone can read exactly what it does at
  [github.com/jessestay/beacon](https://github.com/jessestay/beacon).

Two honest limits: your Muse acts *as you* on your PC, so only install Beacon
on **your own** computer. And the installer isn't code-signed yet, so Windows
shows a SmartScreen warning on first run (click **More info → Run anyway**).

## Install — Windows

You need: a Windows 10 or 11 computer, and about 3 minutes. No downloads, no
setup, no administrator password — everything Beacon needs (Windows
PowerShell and an internet connection) is already on your PC, and Beacon
checks both automatically before it starts.

1. **Download Beacon:** open
   [this page](https://github.com/jessestay/beacon/blob/main/Beacon.exe),
   click the file named **Beacon.exe**, then click **Download**.
2. Open your **Downloads** folder and **double-click Beacon.exe**.
   - If Windows shows a blue screen saying *"Windows protected your PC,"*
     click **More info**, then **Run anyway**.
3. A black window opens and runs a quick health check on your computer.
   This takes a minute or two — that's normal.
4. It asks **one question**: your Muse's bot code. **Your Muse gives you this
   code** (it starts with B) — type it in and press Enter.
5. When you see **"All done,"** press Enter to close the window. You're set!

## What happens after I install it?

Nothing you need to do. Every few minutes, your Muse sees a short "alive"
message — that's just Beacon saying *"I'm here and watching."* When you tell
your Muse something's wrong, it can run a check and tell you what it found.

## How do I remove it?

1. Double-click **Beacon.exe** again.
2. It will tell you Beacon is already installed. Type **REMOVE** and press
   Enter.
3. That's it — Beacon removes itself and stops.

## If something goes wrong

The installer will show you this address if it hits an error — your report
goes straight to the team that builds Beacon:

**[github.com/jessestay/beacon/issues/new](https://github.com/jessestay/beacon/issues/new)**

Tell us what you were doing, and attach a photo or screenshot of the window.
Our team watches that page and picks up new reports automatically.

---

## For technical folks

Beacon polls a Slack channel for `[beacon-cmd:<id>]` messages posted **only**
by the authorized Muse bot id, executes them in PowerShell (60-second timeout,
8KB output cap), and replies in-thread. Outbound HTTPS only — no inbound
ports, no firewall changes. Install is idempotent: diagnose (read-only) →
repair → register a per-user logon task.

| Command | What it does |
|---|---|
| Double-click `Beacon.exe` | Install, or check & repair if already installed |
| `Beacon.exe -SelfTest` | Acceptance tests. Changes nothing, posts nothing. |
| `Beacon.exe -Uninstall` | Remove the logon task and stop. |
| `Beacon.exe -NoLoop` | Diagnose + repair only. |

The `.exe` is a tiny Go launcher (source: `main.go`) that embeds
`Beacon.ps1` and runs it via `powershell.exe -ExecutionPolicy Bypass`.
Build it yourself:

```powershell
GOOS=windows GOARCH=amd64 go build -o Beacon.exe .
```

Tests: `Beacon.Tests.ps1` (Pester v5 — the TDD contract, run on Windows)
and `go test ./...` (launcher unit tests, runs anywhere).

### Security review (v0.3.0)

- **Authorization:** Slack stamps `bot_id` server-side on every bot-posted
  message; it cannot be spoofed through the API (verified against a live bot
  message: `bot_id` present, `user` absent). `Test-BeaconAuthorization`
  accepts only an exact `bot_id` match; human messages and lookalike text are
  rejected. An empty authorized id refuses to start.
- **No inbound attack surface:** outbound HTTPS to `slack.com` only. Windows
  Firewall's default-deny inbound posture is untouched.
- **Credential handling:** token auto-discovered from the local MACF
  `slack-agents/.env`, else pasted via `-AsSecureString` (hidden input);
  stored at `$HOME\Beacon\.token` with inheritance removed and granted only
  to the installing user (`icacls`); never placed on the scheduled-task
  command line.
- **Execution containment:** commands run in a `Start-Job` sandbox with a
  60-second timeout, the job is always removed, output is truncated to 8KB,
  and everything runs as the installing user — no elevation, no new privileges.
- **Replay safety:** the loop ignores all channel history at startup
  (`oldest` = now), dedupes per run, and holds a `Global\BeaconLoop` mutex so
  two copies can't double-execute.
- **Encoding:** the script is pure ASCII and the launcher writes it with a
  UTF-8 BOM — Windows PowerShell 5.1 reads BOM-less scripts as ANSI, which
  caused the v0.2.0 parse errors. Covered by a Pester test.
- **Residual risks:** the exe is unsigned (SmartScreen warning until we
  code-sign); commands execute as the user, so a compromised Muse/bot token
  could run anything — inherent to a remote-admin tool, mitigated by
  you-choosing-the-bot and one-word uninstall. Channel members can read
  command text and results posted in the channel.

### Roadmap

macOS and Linux builds, code signing, and future Muse-specific features.
Bug reports: [github.com/jessestay/beacon/issues](https://github.com/jessestay/beacon/issues) —
monitored automatically; new reports are relayed to the team in Slack.
