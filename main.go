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
	if err := os.WriteFile(ps1Path, []byte(beaconScript), 0600); err != nil {
		fmt.Println("Couldn't unpack Beacon:", err)
		pause()
		os.Exit(1)
	}

	psArgs := append([]string{
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1Path,
	}, flags...)
	cmd := exec.Command("powershell.exe", psArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println()
		fmt.Println("Beacon stopped with an error. If you need help,")
		fmt.Println("take a photo of this window and send it to the person helping you.")
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
