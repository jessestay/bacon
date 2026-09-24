# Beacon.Tests.ps1 -- Pester v5 acceptance tests for Beacon.ps1
#
# TDD contract: Beacon.ps1 MUST satisfy every test in this file.
# Run on the target machine (or CI Windows runner):
#   Invoke-Pester ./Beacon.Tests.ps1
#
# Design rules under test ("it just works" philosophy):
#   1. Zero config: every behavior has a working default.
#   2. Never execute a command that did not come from the authorized bot.
#   3. Never hang: every remote call has a timeout; every command has a timeout.
#   4. Never flood: outputs are truncated, heartbeats are rate-limited.
#   5. Diagnose is read-only; repair is idempotent.
#   6. Pure ASCII script: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
#      so any non-ASCII char can break parsing. The launcher also writes a BOM.

BeforeAll {
    . "$PSScriptRoot/Beacon.ps1"   # dot-source: loads functions, runs nothing
}

Describe "Beacon.ps1 dot-sourcing" {
    It "loads functions without starting the loop or changing the machine" {
        # If dot-sourcing had side effects this test file would never get here.
        (Get-Command ConvertTo-BeaconCommand -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}

Describe "ConvertTo-BeaconCommand (command parsing)" {
    It "extracts id and command text from a well-formed command" {
        $msg = @{ text = "[beacon-cmd:abc123] Get-Date"; ts = "1"; bot_id = "B0C39F2CNHJ" }
        $cmd = ConvertTo-BeaconCommand $msg
        $cmd.Id | Should -Be "abc123"
        $cmd.CommandText | Should -Be "Get-Date"
    }

    It "tolerates extra whitespace after the id" {
        $msg = @{ text = "[beacon-cmd:xyz]    hostname"; ts = "1"; bot_id = "B0C39F2CNHJ" }
        (ConvertTo-BeaconCommand $msg).CommandText | Should -Be "hostname"
    }

    It "returns null for ordinary team chatter" {
        $msg = @{ text = "morning team, here is the draft"; ts = "1"; bot_id = "B0AUJU69" }
        ConvertTo-BeaconCommand $msg | Should -BeNullOrEmpty
    }

    It "returns null for a lookalike prefix without brackets" {
        $msg = @{ text = "beacon-cmd:abc Get-Date"; ts = "1"; bot_id = "B0C39F2CNHJ" }
        ConvertTo-BeaconCommand $msg | Should -BeNullOrEmpty
    }

    It "returns null when the command body is empty" {
        $msg = @{ text = "[beacon-cmd:abc]   "; ts = "1"; bot_id = "B0C39F2CNHJ" }
        ConvertTo-BeaconCommand $msg | Should -BeNullOrEmpty
    }

    It "returns null for a null/empty message" {
        ConvertTo-BeaconCommand $null | Should -BeNullOrEmpty
        ConvertTo-BeaconCommand @{ text = ""; ts = "1" } | Should -BeNullOrEmpty
    }
}

Describe "Test-BeaconAuthorization (who may issue commands)" {
    It "authorizes the configured bot id" {
        $msg = @{ text = "[beacon-cmd:a] whoami"; ts = "1"; bot_id = "B0C39F2CNHJ" }
        Test-BeaconAuthorization $msg "B0C39F2CNHJ" | Should -BeTrue
    }

    It "rejects any other bot" {
        $msg = @{ text = "[beacon-cmd:a] whoami"; ts = "1"; bot_id = "B0AUJU69" }
        Test-BeaconAuthorization $msg "B0C39F2CNHJ" | Should -BeFalse
    }

    It "rejects human users even with a well-formed command" {
        $msg = @{ text = "[beacon-cmd:a] whoami"; ts = "1"; user = "U12QFAS8L" }
        Test-BeaconAuthorization $msg "B0C39F2CNHJ" | Should -BeFalse
    }

    It "rejects messages with no bot_id at all" {
        $msg = @{ text = "[beacon-cmd:a] whoami"; ts = "1" }
        Test-BeaconAuthorization $msg "B0C39F2CNHJ" | Should -BeFalse
    }
}

Describe "Truncate-BeaconOutput (never flood the channel)" {
    It "passes short output through unchanged" {
        Truncate-BeaconOutput "hello" 8000 | Should -Be "hello"
    }

    It "truncates long output and marks it" {
        $long = "x" * 9000
        $out = Truncate-BeaconOutput $long 8000
        $out.Length | Should -BeLessThan 9000
        $out | Should -Match "truncated"
    }

    It "handles empty output" {
        Truncate-BeaconOutput "" 8000 | Should -Be "(no output)"
        Truncate-BeaconOutput $null 8000 | Should -Be "(no output)"
    }
}

Describe "Get-BeaconHeartbeat (rate-limited status)" {
    It "formats a one-line heartbeat starting with the beacon tag" {
        $hb = Get-BeaconHeartbeat @{ AgentTask = "Running"; Port8099 = $true }
        $hb | Should -Match "^\[beacon\] alive"
    }
}

Describe "Install-Beacon idempotency contract" {
    It "exposes Install-Beacon and Uninstall-Beacon functions" {
        (Get-Command Install-Beacon -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        (Get-Command Uninstall-Beacon -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}

Describe "Beacon.ps1 encoding (the v0.2.0 install bug)" {
    It "is pure ASCII so Windows PowerShell 5.1 parses it correctly" {
        $bytes = [IO.File]::ReadAllBytes("$PSScriptRoot/Beacon.ps1")
        $bad = @($bytes | Where-Object { $_ -gt 127 })
        $bad.Count | Should -Be 0
    }

    It "reports version 0.3.5" {
        $script:BeaconVersion | Should -Be "0.3.5"
    }
}

Describe "Invoke-BeaconSelfTest contract" {
    It "exposes a self-test entry point" {
        (Get-Command Invoke-BeaconSelfTest -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}
