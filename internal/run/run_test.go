package run

import (
	"strings"
	"testing"

	"github.com/user/sshvault/internal/vault"
)

func TestArgs(t *testing.T) {
	cases := []struct {
		name string
		h    vault.Host
		want []string
	}{
		{
			name: "default port omits -p, bare user@host",
			h:    vault.Host{User: "deploy", Host: "10.0.1.10"},
			want: []string{"--", "deploy@10.0.1.10"},
		},
		{
			name: "explicit port 22 still omits -p",
			h:    vault.Host{User: "deploy", Host: "10.0.1.10", Port: 22},
			want: []string{"--", "deploy@10.0.1.10"},
		},
		{
			// Regression: a non-standard port must go to -p only, and the
			// destination must NOT carry a :port suffix (ssh can't resolve it).
			name: "non-standard port uses -p, destination has no :port",
			h:    vault.Host{User: "ubuntu", Host: "stg.example.com", Port: 2222},
			want: []string{"-p", "2222", "--", "ubuntu@stg.example.com"},
		},
		{
			name: "no user",
			h:    vault.Host{Host: "192.168.0.5"},
			want: []string{"--", "192.168.0.5"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := Args(c.h)
			if strings.Join(got, " ") != strings.Join(c.want, " ") {
				t.Errorf("Args() = %v, want %v", got, c.want)
			}
		})
	}
}

// A host/user value beginning with "-" must never be parsed by ssh as a flag:
// the "--" guard has to sit immediately before the destination.
func TestArgs_OptionInjectionGuarded(t *testing.T) {
	h := vault.Host{User: "root", Host: "-oProxyCommand=calc"}
	got := Args(h)
	dashDash := -1
	for i, a := range got {
		if a == "--" {
			dashDash = i
		}
	}
	if dashDash == -1 || dashDash != len(got)-2 {
		t.Fatalf("expected `--` immediately before destination, got %v", got)
	}
	if got[len(got)-1] != "root@-oProxyCommand=calc" {
		t.Errorf("destination = %q, want it after `--`", got[len(got)-1])
	}
}
