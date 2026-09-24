<#
.SYNOPSIS
    Beacon v0.3.4 -- the Meta Muse companion for YOUR OWN Windows PC.

.DESCRIPTION
    Beacon is built specifically and only for Meta Muse: your personal AI
    assistant. Install it on your Windows PC and your Muse can check the
    machine's health, fix problems, and help with your work, right from a
    chat with you. Nothing and no one else can use it.

    "It just works" design: double-click (or one command) and it
      1. Diagnoses the machine (agent, local AI, team services) -- details go
         to the log for your Muse; the screen shows only what needs you.
         -- read-only.
      2. Repairs what it can (restarts the agent task, starts Ollama)
         -- idempotent.
      3. Opens a command channel to your Muse over Slack (outbound HTTPS
         only -- no firewall changes, no inbound ports). Commands are
         accepted ONLY from your Muse's bot id. Every command times out;
         output is truncated; history is never re-executed.

    Run with -SelfTest to execute the acceptance tests without changing anything.

.PARAMETER SelfTest
    Run acceptance tests. Changes nothing, posts nothing.

.PARAMETER Install
    Copy to $HOME\Beacon, register a logon scheduled task, start it now.

.PARAMETER Uninstall
    Remove the scheduled task. A running task-installed loop exits on its own.

.PARAMETER NoLoop
    Diagnose + repair only; do not start the command loop.

.PARAMETER Channel
    Slack channel for heartbeats/commands. Default #marketing.

.PARAMETER PollSeconds
    How often to poll Slack for commands. Default 30.

.PARAMETER AuthorizedBotId
    Your Meta Muse's Slack bot id -- ONLY this bot's messages are executed
    as commands. If omitted, Beacon asks once at install. (The id is public;
    your Muse gives you this code; it looks like B0C39F2CNHJ.)

.PARAMETER Token
    Slack bot token. If omitted, Beacon looks for the MACF slack-agents .env,
    then $HOME\Beacon\.token. It never asks for one: if none is found it
    says so plainly and stops.

.EXAMPLE
    .\Beacon.ps1 -SelfTest     # verify on this machine, change nothing
    .\Beacon.ps1 -Install      # set-and-forget: logon task + start now
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$NoLoop,
    [switch]$FromTask,
    [string]$Channel = "#marketing",
    [int]$PollSeconds = 30,
    [string]$AuthorizedBotId = "",
    [string]$Token = ""
)

# Dot-sourced (Pester tests): load functions, run nothing.
if ($MyInvocation.InvocationName -eq '.') { return }

$script:BeaconVersion  = "0.3.4"
$script:BeaconTaskName = "Beacon"
$script:BeaconHome     = Join-Path $env:USERPROFILE "Beacon"
$script:CommandTimeout = 60      # seconds per remote command
$script:MaxOutput      = 8000    # chars per command result
$script:HeartbeatSecs = 600     # heartbeat cadence

function Write-BeaconLog([string]$Message) {
    "[$(Get-Date -Format 'HH:mm:ss')] $Message" | Write-Host
}

# --- Pure functions (covered by Beacon.Tests.ps1) ---

function ConvertTo-BeaconCommand($Message) {
    if (-not $Message) { return $null }
    [string]$text = $Message.text
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $m = [regex]::Match($text, '^\[beacon-cmd:([A-Za-z0-9_-]+)\]\s*(.+?)\s*$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ Id = $m.Groups[1].Value; CommandText = $m.Groups[2].Value }
}

function Test-BeaconAuthorization($Message, [string]$AuthorizedBotId) {
    # Slack stamps bot_id on every message a bot posts; it cannot be spoofed
    # through the API. Human messages carry user instead and are rejected.
    if (-not $Message) { return $false }
    [string]$botId = $Message.bot_id
    if ([string]::IsNullOrWhiteSpace($botId)) { return $false }
    if ([string]::IsNullOrWhiteSpace($AuthorizedBotId)) { return $false }
    return $botId -eq $AuthorizedBotId
}

function Truncate-BeaconOutput($Text, [int]$Max = 8000) {
    [string]$s = [string]$Text
    if ([string]::IsNullOrWhiteSpace($s)) { return "(no output)" }
    $s = $s.Trim()
    if ($s.Length -le $Max) { return $s }
    return $s.Substring(0, $Max) + "`n... [truncated, $($s.Length) total chars]"
}

function Get-BeaconHeartbeat($Diag) {
    $agent = "unknown"; $port = "unknown"
    if ($Diag) {
        if ($Diag.AgentTask) { $agent = $Diag.AgentTask }
        if ($null -ne $Diag.Port8099) { $port = $(if ($Diag.Port8099) { "open" } else { "closed" }) }
    }
    return "[beacon] alive -- v$($script:BeaconVersion) -- agent task: $agent; port 8099: $port"
}

# --- Machine checks (read-only) ---

function Test-BeaconPort([string]$Computer = "127.0.0.1", [int]$Port = 8099, [int]$TimeoutMs = 2000) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Computer, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch { return $false }
    finally { $client.Close() }
}

function Test-BeaconPrereqs {
    Write-BeaconLog "  reaching slack.com to verify internet access..."
    $issues = @()
    if ($PSVersionTable.PSVersion.Major -lt 5) { $issues += "PowerShell 5.1 or newer required" }
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $c = New-Object System.Net.Http.HttpClient
        $c.Timeout = [TimeSpan]::FromSeconds(10)
        $r = $c.GetAsync("https://slack.com/api/api.test").Result
        if (-not $r.IsSuccessStatusCode) { $issues += "slack.com answered HTTP $($r.StatusCode)" }
        $c.Dispose()
    } catch { $issues += "cannot reach slack.com: $($_.Exception.Message)" }
    return @{ Ok = ($issues.Count -eq 0); Issues = $issues }
}

function Find-BeaconToken([string]$ExplicitToken) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) { return $ExplicitToken }

    $candidates = @(
        (Join-Path $env:USERPROFILE "slack-agents\.env"),
        (Join-Path $env:USERPROFILE "MACF\slack-agents\.env"),
        (Join-Path $env:USERPROFILE "MultiAgentCommsFramework\slack-agents\.env"),
        (Join-Path $env:USERPROFILE "ClaudeHeadless\slack-agents\.env"),
        (Join-Path $env:USERPROFILE "Desktop\slack-agents\.env")
    )
    # Also: any running node process whose command line mentions slack-agents
    try {
        $nodes = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -match 'slack-agents' }
        foreach ($n in $nodes) {
            $m = [regex]::Match($n.CommandLine, '([A-Za-z]:\\[^"]*?slack-agents)')
            if ($m.Success) { $candidates += (Join-Path $m.Groups[1].Value ".env") }
        }
    } catch { }

    # Bounded filesystem sweep: the team's .env lives somewhere under the profile.
    # Depth 2 covers ~\slack-agents\.env and ~\MACF\slack-agents\.env. Fast, no prompts.
    try {
        $sweepRoots = @($env:USERPROFILE, (Join-Path $env:USERPROFILE "Desktop"))
        foreach ($root in $sweepRoots) {
            if (-not (Test-Path $root)) { continue }
            $hits = Get-ChildItem -Path $root -Filter ".env" -Recurse -Depth 2 -File `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.DirectoryName -match 'slack-agents' } |
                Select-Object -First 2
            foreach ($h in $hits) { $candidates += $h.FullName }
        }
    } catch { }

    foreach ($p in $candidates | Select-Object -Unique) {
        if (-not (Test-Path $p)) { continue }
        foreach ($line in (Get-Content $p -ErrorAction SilentlyContinue)) {
            $m = [regex]::Match($line, '^\s*SLACK_BOT_TOKEN\s*=\s*(xoxb-[^\s\r\n]+)')
            if ($m.Success) {
                Write-BeaconLog "Slack token found ($p)"
                return $m.Groups[1].Value
            }
        }
    }
    return $null
}

function Get-BeaconDiagnosis {
    Write-BeaconLog "  checking this PC's health..."
    $d = [ordered]@{
        Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Computer  = $env:COMPUTERNAME
        User      = $env:USERNAME
    }

    try {
        if (Get-Command tailscale -ErrorAction SilentlyContinue) {
            $ts = (& tailscale status 2>&1 | Out-String).Trim().Split("`n")[0]
            $d.Tailscale = if ($ts) { $ts } else { "up (no output)" }
        } else { $d.Tailscale = "not installed" }
    } catch { $d.Tailscale = "error: $($_.Exception.Message)" }

    try {
        $t = Get-ScheduledTask -TaskName "Jarvis-DesktopAgent" -ErrorAction Stop
        $d.AgentTask = $t.State.ToString()
    } catch { $d.AgentTask = "not found" }

    try { $d.Port8099 = Test-BeaconPort -Port 8099 }
    catch { $d.Port8099 = $false }

    try {
        if (Get-Command ollama -ErrorAction SilentlyContinue) {
            $models = (& ollama list 2>&1 | Out-String).Trim().Split("`n")
            $d.Ollama = if ($models.Count -gt 1) { "$($models.Count - 1) model(s)" } else { "installed, not serving" }
        } else { $d.Ollama = "not installed" }
    } catch { $d.Ollama = "error: $($_.Exception.Message)" }

    try {
        $team = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -match 'slack-agents|vikunja-relay' })
        $d.NodeTeam = if ($team.Count -gt 0) { "$($team.Count) process(es)" } else { "not running" }
    } catch { $d.NodeTeam = "unknown" }

    try {
        $keyPresent = $false
        foreach ($p in @((Join-Path $env:USERPROFILE "slack-agents\.env"),
                         (Join-Path $env:USERPROFILE "MACF\slack-agents\.env"),
                         (Join-Path $env:USERPROFILE "MultiAgentCommsFramework\slack-agents\.env"))) {
            if ((Test-Path $p) -and (Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*ANTHROPIC_API_KEY\s*=\s*\S' })) {
                $keyPresent = $true; break
            }
        }
        $d.AnthropicKey = if ($keyPresent) { "present" } else { "absent" }
    } catch { $d.AnthropicKey = "unknown" }

    return $d
}

function Show-BeaconDiagnosis($Diag) {
    # The full table stays in the log for the Muse. The screen shows only
    # what a person would act on -- internal plumbing stays out of sight.
    Write-BeaconLog "-- Health check --------------------------------"
    $notes = @()
    if ($Diag.AgentTask -eq "not found") {
        $notes += "desktop agent not found -- your Muse can set it up if needed"
    }
    if ($Diag.Ollama -eq "not installed") {
        $notes += "local AI not installed (optional -- your Muse works without it)"
    }
    if ($notes.Count -eq 0) { Write-BeaconLog "  All good." }
    else { foreach ($n in $notes) { Write-BeaconLog "  - $n" } }
    Write-BeaconLog "  Full details were saved to the Beacon log for your Muse."
}

# --- Repair (idempotent) ---

function Repair-BeaconAgent($Diag) {
    if ($Diag.Port8099) { Write-BeaconLog "Port 8099 already open -- agent is up."; return }

    $task = Get-ScheduledTask -TaskName "Jarvis-DesktopAgent" -ErrorAction SilentlyContinue
    if ($task) {
        try {
            Start-ScheduledTask -TaskName "Jarvis-DesktopAgent" -ErrorAction Stop
            Write-BeaconLog "Agent task started; waiting for port 8099..."
            Start-Sleep -Seconds 8
            if (Test-BeaconPort -Port 8099) { Write-BeaconLog "Port 8099 is open -- agent repaired." }
            else { Write-BeaconLog "Port 8099 still closed after task start." }
        } catch { Write-BeaconLog "Could not start agent task: $($_.Exception.Message)" }
    } else {
        Write-BeaconLog "Agent task 'Jarvis-DesktopAgent' not found -- skipping agent repair."
    }

    if (($Diag.Ollama -eq "installed, not serving") -and (Get-Command ollama -ErrorAction SilentlyContinue)) {
        try {
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction Stop
            Write-BeaconLog "Ollama serve started."
        } catch { Write-BeaconLog "Could not start Ollama: $($_.Exception.Message)" }
    }
}

# --- Slack wire (outbound HTTPS only) ---

function Invoke-BeaconSlackApi([string]$Token, [string]$Method, [hashtable]$Params = @{}, [string]$HttpMethod = "GET") {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    try {
        $client.DefaultRequestHeaders.Authorization =
            New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $Token)
        $url = "https://slack.com/api/$Method"
        if ($HttpMethod -eq "GET") {
            $q = ($Params.GetEnumerator() | ForEach-Object {
                [uri]::EscapeDataString($_.Key) + "=" + [uri]::EscapeDataString([string]$_.Value)
            }) -join "&"
            if ($q) { $url += "?$q" }
            $resp = $client.GetAsync($url).Result
        } else {
            $json = ($Params | ConvertTo-Json -Depth 5)
            $content = New-Object System.Net.Http.StringContent($json, [Text.Encoding]::UTF8, "application/json")
            $resp = $client.PostAsync($url, $content).Result
        }
        $body = $resp.Content.ReadAsStringAsync().Result
        return ($body | ConvertFrom-Json)
    } finally { $client.Dispose() }
}

function Get-BeaconChannelId([string]$Token, [string]$ChannelName) {
    $name = $ChannelName.TrimStart("#")
    $list = Invoke-BeaconSlackApi $Token "conversations.list" @{ types = "public_channel"; limit = 200 }
    if (-not $list.ok) { throw "conversations.list failed: $($list.error)" }
    $ch = $list.channels | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $ch) { throw "channel '$ChannelName' not found or bot is not a member" }
    return $ch.id
}

function Invoke-BeaconCommand([string]$CommandText, [int]$TimeoutSec = 60) {
    $job = Start-Job -ScriptBlock {
        param($c)
        try { Invoke-Expression $c 2>&1 | Out-String }
        catch { "ERROR: $($_.Exception.Message)" }
    } -ArgumentList $CommandText
    try {
        $finished = Wait-Job $job -Timeout $TimeoutSec
        if ($finished) { $out = (Receive-Job $job | Out-String) }
        else { Stop-Job $job; $out = "(timed out after ${TimeoutSec}s -- job stopped)" }
    } finally { Remove-Job $job -Force -ErrorAction SilentlyContinue }
    return (Truncate-BeaconOutput $out $script:MaxOutput)
}

function Start-BeaconLoop([string]$Token, [string]$Channel, [int]$PollSeconds, [string]$AuthorizedBotId) {
    # Single instance: a second loop (double-click while the task runs) exits.
    $mutex = New-Object Threading.Mutex($false, "Global\BeaconLoop")
    if (-not $mutex.WaitOne(0)) {
        Write-BeaconLog "Beacon is already running -- exiting this copy."
        exit 0
    }
    try { $channelId = Get-BeaconChannelId $Token $Channel }
    catch {
        Write-BeaconLog "Cannot start loop: $($_.Exception.Message)"
        Write-BeaconLog "Make sure your Muse's bot is a member of $Channel and the token is valid."
        exit 1
    }
    Write-BeaconLog "Beacon loop live in $Channel. Commands accepted only from your Muse (bot $AuthorizedBotId)."
    Write-BeaconLog "Your Muse posts  [beacon-cmd:<id>] <powershell>  to run a command."

    $seen = New-Object System.Collections.Generic.HashSet[string]
    # Ignore everything already in the channel: commands are never re-executed,
    # even across restarts. Only messages posted after startup are eligible.
    $lastTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() + ".000000"
    $lastHeartbeat = [DateTime]::MinValue

    # Announce
    try {
        Invoke-BeaconSlackApi $Token "chat.postMessage" @{
            channel = $channelId; text = (Get-BeaconHeartbeat (Get-BeaconDiagnosis))
        } -HttpMethod "POST" | Out-Null
        $lastHeartbeat = Get-Date
    } catch { Write-BeaconLog "Heartbeat post failed: $($_.Exception.Message)" }

    while ($true) {
        if ($FromTask -and -not (Get-ScheduledTask -TaskName $script:BeaconTaskName -ErrorAction SilentlyContinue)) {
            Write-BeaconLog "Task uninstalled -- exiting loop."
            return
        }
        try {
            $hist = Invoke-BeaconSlackApi $Token "conversations.history" @{
                channel = $channelId; oldest = $lastTs; limit = 20; inclusive = "false"
            }
            if ($hist.ok -and $hist.messages) {
                foreach ($m in $hist.messages) {
                    $key = "$($m.ts)|$($m.text)"
                    if ($seen.Contains($key)) { continue }
                    $seen.Add($key) | Out-Null
                    if ([double]$m.ts -gt [double]$lastTs) { $lastTs = $m.ts }
                    $cmd = ConvertTo-BeaconCommand $m
                    if ($cmd -and (Test-BeaconAuthorization $m $AuthorizedBotId)) {
                        Write-BeaconLog "cmd $($cmd.Id): $($cmd.CommandText)"
                        $result = Invoke-BeaconCommand $cmd.CommandText $script:CommandTimeout
                        $reply = "[beacon-result:$($cmd.Id)]`n``````powershell`n$result`n``````"
                        try {
                            Invoke-BeaconSlackApi $Token "chat.postMessage" @{
                                channel = $channelId; thread_ts = $m.ts; text = $reply
                            } -HttpMethod "POST" | Out-Null
                        } catch { Write-BeaconLog "Result post failed: $($_.Exception.Message)" }
                    }
                }
            }
        } catch { Write-BeaconLog "Poll error: $($_.Exception.Message)" }

        if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge $script:HeartbeatSecs) {
            try {
                Invoke-BeaconSlackApi $Token "chat.postMessage" @{
                    channel = $channelId; text = (Get-BeaconHeartbeat (Get-BeaconDiagnosis))
                } -HttpMethod "POST" | Out-Null
                $lastHeartbeat = Get-Date
            } catch { Write-BeaconLog "Heartbeat post failed: $($_.Exception.Message)" }
        }
        Start-Sleep -Seconds $PollSeconds
    }
}

# --- Install / uninstall ---

function Install-Beacon([string]$Token, [string]$Channel, [int]$PollSeconds, [string]$AuthorizedBotId) {
    if (-not (Test-Path $script:BeaconHome)) { New-Item -ItemType Directory -Path $script:BeaconHome | Out-Null }
    $dest = Join-Path $script:BeaconHome "Beacon.ps1"
    Copy-Item -Path $PSCommandPath -Destination $dest -Force
    Write-BeaconLog "Installed to $dest"

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $tf = Join-Path $script:BeaconHome ".token"
        $Token | Out-File -FilePath $tf -NoNewline -Encoding ascii
        & icacls $tf /inheritance:r /grant:r "$env:USERNAME:(R,W)" | Out-Null
    }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument (
        "-NoProfile -ExecutionPolicy Bypass -File `"$dest`" -FromTask " +
        "-Channel `"$Channel`" -PollSeconds $PollSeconds -AuthorizedBotId `"$AuthorizedBotId`""
    )
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    Register-ScheduledTask -TaskName $script:BeaconTaskName -Action $action -Trigger $trigger -Force | Out-Null
    Write-BeaconLog "Logon task '$($script:BeaconTaskName)' registered."
    Start-ScheduledTask -TaskName $script:BeaconTaskName
    Write-BeaconLog "Beacon task started."
}

function Uninstall-Beacon {
    $t = Get-ScheduledTask -TaskName $script:BeaconTaskName -ErrorAction SilentlyContinue
    if ($t) {
        try { Stop-ScheduledTask -TaskName $script:BeaconTaskName -ErrorAction SilentlyContinue } catch { }
        Unregister-ScheduledTask -TaskName $script:BeaconTaskName -Confirm:$false
        Write-BeaconLog "Task '$($script:BeaconTaskName)' removed."
    } else { Write-BeaconLog "No Beacon task to remove." }
}

# --- Self-test (acceptance tests, zero side effects) ---

function Invoke-BeaconSelfTest {
    $script:fail = 0
    function Assert-True([bool]$cond, [string]$name) {
        if ($cond) { Write-BeaconLog "PASS  $name" }
        else { Write-BeaconLog "FAIL  $name"; $script:fail++ }
    }

    $m = ConvertTo-BeaconCommand @{ text = "[beacon-cmd:abc123] Get-Date"; ts = "1"; bot_id = "B0C39F2CNHJ" }
    Assert-True ($m.Id -eq "abc123" -and $m.CommandText -eq "Get-Date") "parse well-formed command"
    Assert-True ((ConvertTo-BeaconCommand @{ text = "hello team"; ts = "1" }) -eq $null) "ignore chatter"
    Assert-True ((ConvertTo-BeaconCommand @{ text = "[beacon-cmd:x]  "; ts = "1" }) -eq $null) "reject empty command"
    Assert-True ((ConvertTo-BeaconCommand $null) -eq $null) "handle null message"

    Assert-True (Test-BeaconAuthorization @{ text = "x"; bot_id = "B0C39F2CNHJ" } "B0C39F2CNHJ") "authorize own Muse bot"
    Assert-True (-not (Test-BeaconAuthorization @{ text = "x"; bot_id = "B0AUJU69" } "B0C39F2CNHJ")) "reject other bot"
    Assert-True (-not (Test-BeaconAuthorization @{ text = "x"; user = "U1" } "B0C39F2CNHJ")) "reject human user"
    Assert-True (-not (Test-BeaconAuthorization @{ text = "x"; bot_id = "B0C39F2CNHJ" } "")) "reject empty authorized id"

    Assert-True ((Truncate-BeaconOutput "hi" 8000) -eq "hi") "short output unchanged"
    Assert-True ((Truncate-BeaconOutput ("x" * 9000) 8000) -match "truncated") "long output truncated"
    Assert-True ((Truncate-BeaconOutput "" 8000) -eq "(no output)") "empty output marker"

    Assert-True ((Get-BeaconHeartbeat @{ AgentTask = "Running"; Port8099 = $true }) -match "^\[beacon\] alive") "heartbeat format"

    $pre = Test-BeaconPrereqs
    Assert-True ($pre.Ok) "prereqs: $($pre.Issues -join '; ')"
    $diag = Get-BeaconDiagnosis   # read-only by design
    Assert-True ($diag.Contains("Port8099") -and $diag.Contains("AgentTask")) "diagnosis contract"
    $tok = Find-BeaconToken ""
    Write-BeaconLog "INFO  token discovery: $(if ($tok) { 'found' } else { 'not found (install will stop with a plain message)' })"

    if ($script:fail -eq 0) { Write-BeaconLog "SELF-TEST: all passed."; return 0 }
    Write-BeaconLog "SELF-TEST: $($script:fail) failure(s)."; return 1
}

# --- Main ---

Write-BeaconLog "Beacon v$($script:BeaconVersion) -- the Meta Muse companion for this PC."

if ($SelfTest) { exit (Invoke-BeaconSelfTest) }
if ($Uninstall) { Uninstall-Beacon; exit 0 }

Write-BeaconLog "Step 1 of 3: checking prerequisites..."
Write-Progress -Activity "Beacon install" -Status "Step 1 of 3: checking prerequisites..." -PercentComplete 10
$pre = Test-BeaconPrereqs
if (-not $pre.Ok) {
    Write-Progress -Activity "Beacon install" -Completed
    Write-BeaconLog "Prerequisites failed:"
    $pre.Issues | ForEach-Object { Write-BeaconLog "  - $_" }
    exit 1
}

Write-BeaconLog "Step 2 of 3: running health check (a minute or two)..."
Write-Progress -Activity "Beacon install" -Status "Step 2 of 3: running health check..." -PercentComplete 40
$diag = Get-BeaconDiagnosis
Show-BeaconDiagnosis $diag
Write-BeaconLog "Step 3 of 3: repairing anything broken..."
Write-Progress -Activity "Beacon install" -Status "Step 3 of 3: repairing anything broken..." -PercentComplete 70
Repair-BeaconAgent $diag
Write-Progress -Activity "Beacon install" -Completed

if ($NoLoop) { Write-BeaconLog "Done (NoLoop)."; exit 0 }

if ([string]::IsNullOrWhiteSpace($AuthorizedBotId)) {
    if ($FromTask) { Write-BeaconLog "No AuthorizedBotId and not interactive -- exiting."; exit 1 }
    Write-BeaconLog "Beacon works only with your Meta Muse -- your personal AI assistant."
    Write-BeaconLog "Paste your Muse's Slack bot ID (starts with B, e.g. B0C39F2CNHJ)."
    Write-BeaconLog "Your Muse gives you this code. Nothing else can ever send commands."
    $AuthorizedBotId = (Read-Host "Muse bot ID").Trim()
}
if ([string]::IsNullOrWhiteSpace($AuthorizedBotId)) {
    Write-BeaconLog "No authorized bot -- refusing to start the loop without one."
    exit 1
}

$token = Find-BeaconToken $Token
if ([string]::IsNullOrWhiteSpace($token)) {
    $tf = Join-Path $script:BeaconHome ".token"
    if (Test-Path $tf) { $token = (Get-Content $tf -Raw).Trim() }
}
if ([string]::IsNullOrWhiteSpace($token)) {
    # No interactive token prompt, ever: a public user should never care
    # about Slack tokens. Either we find the connection or we say so plainly.
    Write-BeaconLog ""
    Write-BeaconLog "Beacon couldn't find your Muse's Slack connection on this PC."
    Write-BeaconLog "Ask your Muse to set it up, then double-click Beacon again."
    exit 1
}

if ($Install) { Install-Beacon $token $Channel $PollSeconds $AuthorizedBotId; exit 0 }

Start-BeaconLoop $token $Channel $PollSeconds $AuthorizedBotId
