package main

import (
	"reflect"
	"strings"
	"testing"
)

func TestEmbeddedScriptPresent(t *testing.T) {
	if strings.TrimSpace(beaconScript) == "" {
		t.Fatal("embedded Beacon.ps1 is empty")
	}
	for _, want := range []string{"Install-Beacon", "Uninstall-Beacon", "AuthorizedBotId", "-SelfTest", "beacon-cmd", "Write-BeaconLog"} {
		if !strings.Contains(beaconScript, want) {
			t.Errorf("embedded script missing %q", want)
		}
	}
}

func TestResolveAction(t *testing.T) {
	cases := []struct {
		name      string
		installed bool
		args      []string
		menuInput string
		want      []string
	}{
		{"fresh double-click installs", false, nil, "", []string{"-Install"}},
		{"installed, Enter pressed, repairs", true, nil, "\n", []string{"-Install"}},
		{"installed, REMOVE uninstalls", true, nil, "remove\n", []string{"-Uninstall"}},
		{"installed, REMOVE case-insensitive", true, nil, "REMOVE\n", []string{"-Uninstall"}},
		{"explicit args pass through", true, []string{"-SelfTest"}, "", []string{"-SelfTest"}},
		{"explicit uninstall passes through", false, []string{"-Uninstall"}, "", []string{"-Uninstall"}},
	}
	for _, c := range cases {
		got := resolveAction(c.installed, c.args, c.menuInput)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}
