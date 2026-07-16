package run

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/user/sshvault/internal/vault"
)

// publicKeyPrefixes are the algorithm tokens a valid SSH *public* key line
// starts with. We check these so we never append a private key (or garbage)
// to a remote authorized_keys file.
var publicKeyPrefixes = []string{
	"ssh-ed25519", "ssh-rsa", "ssh-dss",
	"ecdsa-sha2-", "sk-ssh-ed25519@", "sk-ecdsa-sha2-",
}

// looksLikePublicKey reports whether s is a single OpenSSH public key line.
func looksLikePublicKey(s string) bool {
	for _, p := range publicKeyPrefixes {
		if strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

// portArgs returns ["-p", "N"] for a non-standard port, or nil.
func portArgs(h vault.Host) []string {
	if h.Port != 0 && h.Port != 22 {
		return []string{"-p", strconv.Itoa(h.Port)}
	}
	return nil
}

// CopyIDArgs builds the ssh-copy-id argv (without the program name) for h.
func CopyIDArgs(h vault.Host, pubKeyPath string) []string {
	args := portArgs(h)
	if pubKeyPath != "" {
		args = append(args, "-i", pubKeyPath)
	}
	// ssh-copy-id has no reliable "--" separator; the destination is last.
	return append(args, h.SSHArg())
}

// remoteInstallScript returns a POSIX-sh snippet that appends pub to the
// remote authorized_keys (idempotently) with correct permissions. pub is
// embedded as a single-quoted literal, so any quote in it is escaped.
func remoteInstallScript(pub string) string {
	q := "'" + strings.ReplaceAll(pub, "'", `'\''`) + "'"
	return "set -e; umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; " +
		"touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; " +
		"if grep -qxF " + q + " ~/.ssh/authorized_keys; then " +
		"echo '[sshvault] key already present'; else " +
		"printf '%s\\n' " + q + " >> ~/.ssh/authorized_keys; " +
		"echo '[sshvault] key installed'; fi"
}

// CopyID installs the public key at pubKeyPath into h's authorized_keys.
// It prefers ssh-copy-id and falls back to a manual append over ssh. The
// server prompts for a password once (whatever ssh/ssh-copy-id would ask).
func CopyID(h vault.Host, pubKeyPath string) error {
	data, err := os.ReadFile(pubKeyPath)
	if err != nil {
		return fmt.Errorf("read public key %s: %w", pubKeyPath, err)
	}
	pub := strings.TrimSpace(string(data))
	if !looksLikePublicKey(pub) {
		return fmt.Errorf("%s does not look like an SSH public key — pass the .pub file", pubKeyPath)
	}

	// Preferred path: ssh-copy-id (handles edge cases, agents, key types).
	if _, err := exec.LookPath("ssh-copy-id"); err == nil {
		args := CopyIDArgs(h, pubKeyPath)
		fmt.Fprintf(os.Stderr, "[ sshvault ] → ssh-copy-id %s\n", strings.Join(args, " "))
		if runCmd("ssh-copy-id", args) == nil {
			return nil
		}
		fmt.Fprintln(os.Stderr, "[ sshvault ] ssh-copy-id failed — falling back to manual install")
	}

	// Fallback: append manually over ssh. "--" guards a host beginning with '-'.
	args := append(portArgs(h), "--", h.SSHArg(), remoteInstallScript(pub))
	fmt.Fprintf(os.Stderr, "[ sshvault ] → ssh %s (manual install)\n", h.SSHArg())
	return runCmd("ssh", args)
}

// runCmd runs an interactive command wired to the current stdio.
func runCmd(name string, args []string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	return cmd.Run()
}
