# Beacon

**Let someone you trust fix your computer from far away.**

## What is Beacon?

Beacon is a small, free program for Windows computers. Once it's installed,
a person **you** choose — your son or daughter, a grandchild, your IT person —
can check on your computer and fix problems from their own home, using a
messaging app called Slack. Nobody has to drive anywhere, and nobody has to
talk you through confusing steps over the phone.

## Why would I install this?

- When your computer starts acting strange, the person helping you can take a
  look right away instead of waiting for a visit.
- No more reading long error messages aloud over the phone. They can see
  what's happening and fix it directly.
- It works quietly in the background. After installing, you don't have to do
  a thing.

## Is it safe?

- **Only the one person you approve** can send commands to your computer.
  Not strangers, not other programs, not anyone else.
- Your files are never sent anywhere. Only short answers go back, and only
  to that one person in your own private channel.
- You can remove Beacon at any time (see below). The moment it's removed,
  it stops completely.
- Beacon is free and open-source — anyone can read exactly what it does at
  [github.com/jessestay/beacon](https://github.com/jessestay/beacon).
- Only install Beacon on **your own** computer, and only when someone you
  trust asks you to.

## Install — Windows

You need: a Windows 10 or 11 computer, and about 3 minutes.

1. **Download Beacon:** open
   [this page](https://github.com/jessestay/beacon/blob/main/Beacon.exe),
   click the file named **Beacon.exe**, then click **Download**.
2. Open your **Downloads** folder and **double-click Beacon.exe**.
   - Windows may show a blue screen saying *"Windows protected your PC."*
     This is normal for new programs. Click **More info**, then **Run anyway**.
3. A black window opens and runs a quick health check on your computer.
   This takes a minute or two — that's normal.
4. It asks **one question**: a code that identifies the person allowed to
   help you. **The person helping you will give you this code** — type it in
   and press Enter.
5. When you see **"All done,"** press Enter to close the window. You're set!

## What happens after I install it?

Nothing you need to do. Every few minutes, your helper sees a short "alive"
message — that's just Beacon saying *"I'm here and watching."* When you tell
them something's wrong, they can run a check and tell you what they found.

## How do I remove it?

1. Double-click **Beacon.exe** again.
2. It will tell you Beacon is already installed. Type **REMOVE** and press
   Enter.
3. That's it — Beacon removes itself and stops.

## If something looks wrong

If the black window shows red text or an error message: don't worry, and
don't close it. **Take a photo of the screen with your phone** and send it to
the person helping you. They'll know what to do.

---

## For technical folks

Beacon polls a Slack channel for `[beacon-cmd:<id>]` messages posted **only**
by the authorized bot ID configured at install, executes them in PowerShell
with a 60-second timeout, truncates output to 8KB, and replies in-thread.
Outbound HTTPS only — no inbound ports, no firewall changes. Install is
idempotent: diagnose (read-only) → repair → register a per-user logon task.

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

**Trust model (v0.2.0):** commands execute only from the bot ID you approve
at install; the Slack token is auto-discovered from the local MACF
`slack-agents/.env` if present, otherwise asked for once, and stored at
`$HOME\Beacon\.token` ACL'd to your Windows user. No secrets are posted to
Slack. The exe is unsigned, so Windows SmartScreen shows "More info → Run
anyway" on first launch.

**Roadmap:** macOS and Linux builds are planned for a future release. When
the desktop MACF team is back online, the CTO owns this repo: harden the
trust model (per-command allowlist, signed commands) and keep the suites green.
