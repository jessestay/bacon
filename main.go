// Beacon.exe — the double-click installer for Beacon.
//
// It carries Beacon.ps1 inside itself, writes it to a temp folder, and runs
// it with PowerShell. No setup, no commands to type, no settings to learn.
//
//	Double-click            install (or check & repair if already installed)
//	Beacon.exe -SelfTest    run the acceptance tests, change nothing
//	Beacon.exe -Uninstall   remove Beacon from this computer
package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

//go:embed Beacon.ps1
var beaconScript string

// resolveAction decides which Beacon.ps1 flags to run.
// Pure function — covered by unit tests.
func resolveAction(installed bool, args []string, menuInput string) []string {
	if len(args) > 0 {
		return args
	}
	if installed {
		if strings.EqualFold(strings.TrimSpace(menuInput), "remove") {
			return []string{"-Uninstall"}
		}
		return []string{"-Install"}
	}
	return []string{"-Install"}
}

func alreadyInstalled() bool {
	home, err := os.UserHomeDir()
	if err != nil {
		return false
	}
	info, err := os.Stat(filepath.Join(home, "Beacon", "Beacon.ps1"))
	return err == nil && !info.IsDir()
}

func main() {
	if strings.TrimSpace(beaconScript) == "" {
		fmt.Println("Beacon.exe is damaged (empty script). Please download it again.")
		pause()
		os.Exit(1)
	}

	args := os.Args[1:]
	menuInput := ""
	if len(args) == 0 && alreadyInstalled() {
		fmt.Println("Beacon is already on this computer.")
		fmt.Println()
		fmt.Println("  Press Enter to check it and fix anything broken,")
		fmt.Println("  or type REMOVE and press Enter to take it off this computer.")
		fmt.Print("> ")
		var line [512]byte
		n, _ := os.Stdin.Read(line[:])
		menuInput = string(line[:n])
	}

	flags := resolveAction(alreadyInstalled(), args, menuInput)

	tmpDir, err := os.MkdirTemp("", "beacon")
	if err != nil {
		fmt.Println("Couldn't make a temp folder:", err)
		pause()
		os.Exit(1)
	}
	defer os.RemoveAll(tmpDir)

	ps1Path := filepath.Join(tmpDir, "Beacon.ps1")
	// UTF-8 BOM: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI,
	// which mis-decodes any non-ASCII byte and breaks parsing (v0.2.0 bug).
	// The script itself is pure ASCII; the BOM is belt and suspenders.
	scriptBytes := append([]byte{0xEF, 0xBB, 0xBF}, []byte(beaconScript)...)
	if err := os.WriteFile(ps1Path, scriptBytes, 0600); err != nil {
		fmt.Println("Couldn't unpack Beacon:", err)
		pause()
		os.Exit(1)
	}

	psArgs := append([]string{
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1Path,
	}, flags...)
	fmt.Println("Beacon is starting. First launch can take a minute --")
	fmt.Println("Windows PowerShell is warming up. Please wait...")
	fmt.Println()
	cmd := exec.Command("powershell.exe", psArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println()
		fmt.Println("Something went wrong. Please report it so it can be fixed:")
		fmt.Println("  https://github.com/jessestay/beacon/issues/new")
		fmt.Println("Tell us what you were doing, and attach a photo or")
		fmt.Println("screenshot of this window.")
		pause()
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("All done.")
	pause()
}

func pause() {
	fmt.Println("Press Enter to close this window.")
	var line [8]byte
	os.Stdin.Read(line[:])
}
