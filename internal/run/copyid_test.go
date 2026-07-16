package run

import (
	"strings"
	"testing"

	"github.com/user/sshvault/internal/vault"
)

func TestLooksLikePublicKey(t *testing.T) {
	valid := []string{
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 user@host",
		"ssh-rsa AAAAB3NzaC1yc2E user@host",
		"ecdsa-sha2-nistp256 AAAA... user@host",
		"sk-ssh-ed25519@openssh.com AAAA... user@host",
	}
	for _, s := range valid {
		if !looksLikePublicKey(s) {
			t.Errorf("expected %q to be recognized as a public key", s)
		}
	}
	invalid := []string{
		"",
		"-----BEGIN OPENSSH PRIVATE KEY-----",
		"not a key",
		"password123",
	}
	for _, s := range invalid {
		if looksLikePublicKey(s) {
			t.Errorf("expected %q to be rejected", s)
		}
	}
}

func TestCopyIDArgs(t *testing.T) {
	cases := []struct {
		name string
		h    vault.Host
		key  string
		want []string
	}{
		{
			name: "default port, with key",
			h:    vault.Host{User: "deploy", Host: "10.0.1.10"},
			key:  "/home/u/.ssh/id_ed25519.pub",
			want: []string{"-i", "/home/u/.ssh/id_ed25519.pub", "deploy@10.0.1.10"},
		},
		{
			name: "non-standard port",
			h:    vault.Host{User: "ubuntu", Host: "stg", Port: 2222},
			key:  "k.pub",
			want: []string{"-p", "2222", "-i", "k.pub", "ubuntu@stg"},
		},
		{
			name: "no key",
			h:    vault.Host{User: "root", Host: "h"},
			key:  "",
			want: []string{"root@h"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := strings.Join(CopyIDArgs(c.h, c.key), " ")
			if got != strings.Join(c.want, " ") {
				t.Errorf("CopyIDArgs = %q, want %q", got, strings.Join(c.want, " "))
			}
		})
	}
}

func TestRemoteInstallScript(t *testing.T) {
	pub := "ssh-ed25519 AAAAKEY user@host"
	s := remoteInstallScript(pub)
	for _, want := range []string{
		"umask 077",
		"chmod 700 ~/.ssh",
		"chmod 600 ~/.ssh/authorized_keys",
		"grep -qxF", // idempotent check
		pub,         // the key is embedded
	} {
		if !strings.Contains(s, want) {
			t.Errorf("script missing %q\nscript: %s", want, s)
		}
	}
}

// A single quote in the key comment must be escaped so it can't break out of
// the single-quoted shell literal.
func TestRemoteInstallScript_EscapesQuotes(t *testing.T) {
	pub := "ssh-ed25519 AAAAKEY o'brien@host"
	s := remoteInstallScript(pub)
	if strings.Contains(s, `o'brien@host'`) {
		t.Errorf("single quote not escaped: %s", s)
	}
	if !strings.Contains(s, `o'\''brien`) {
		t.Errorf("expected shell-escaped quote (o'\\''brien) in: %s", s)
	}
}
