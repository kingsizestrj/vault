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

// Connect runs `ssh user@host[:port]` and blocks until it exits.
// Exit codes are propagated.
func Connect(h vault.Host) error {
	args := []string{"ssh"}
	if h.Port != 0 && h.Port != 22 {
		args = append(args, "-p", strconv.Itoa(h.Port))
	}
	args = append(args, h.SSHArg())

	fmt.Fprintf(os.Stderr, "[ sshvault ] → ssh %s\n", strings.Join(args[1:], " "))

	cmd := exec.Command("ssh", args[1:]...)
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
