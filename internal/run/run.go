// Package run execs the user's ssh command, replacing this process image.
// All other commands (list, edit, add, remove) finish before this is called.
package run

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/user/sshvault/internal/vault"
)

// Args builds the ssh argv (without the leading "ssh" program name) for h.
// The port is passed via -p; the destination is a bare user@host. A literal
// "--" precedes the destination so a host/user value beginning with "-" (from
// a synced hosts.toml) can't be smuggled in as an ssh option flag.
func Args(h vault.Host) []string {
	var args []string
	if h.Port != 0 && h.Port != 22 {
		args = append(args, "-p", strconv.Itoa(h.Port))
	}
	args = append(args, "--", h.SSHArg())
	return args
}

// Connect runs `ssh [-p port] -- user@host` and blocks until it exits.
// Exit codes are propagated.
func Connect(h vault.Host) error {
	args := Args(h)

	fmt.Fprintf(os.Stderr, "[ sshvault ] → ssh %s\n", strings.Join(args, " "))

	cmd := exec.Command("ssh", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		return err
	}
	return nil
}
