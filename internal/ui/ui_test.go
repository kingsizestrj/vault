package ui

import (
	"testing"

	"github.com/user/sshvault/internal/vault"
)

// applyFilter must not mutate the master host list. Regression test for the
// `out := m.hosts[:0]` aliasing bug, where filtering overwrote m.hosts in
// place and made hosts vanish / duplicate once the query was cleared.
func TestApplyFilter_DoesNotCorruptMasterList(t *testing.T) {
	hosts := []vault.Host{
		{Alias: "alpha", Host: "a"},
		{Alias: "beta", Host: "b"},
		{Alias: "gamma", Host: "g"},
		{Alias: "delta", Host: "d"},
	}
	m := &model{hosts: hosts, filtered: hosts}

	// Filter down to a single match, then clear the query.
	m.query = "gamma"
	m.applyFilter()
	if len(m.filtered) != 1 || m.filtered[0].Alias != "gamma" {
		t.Fatalf("filter for gamma got %v", aliases(m.filtered))
	}

	m.query = ""
	m.applyFilter()

	want := []string{"alpha", "beta", "gamma", "delta"}
	got := aliases(m.filtered)
	if len(got) != len(want) {
		t.Fatalf("master list corrupted after filter+clear: got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("master list corrupted at %d: got %v, want %v", i, got, want)
		}
	}
}

func aliases(hs []vault.Host) []string {
	out := make([]string, len(hs))
	for i, h := range hs {
		out[i] = h.Alias
	}
	return out
}
