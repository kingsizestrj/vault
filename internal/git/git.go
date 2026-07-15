// Package git wraps the `git` CLI to manage the vault repository.
//
// We don't shell out to libgit2 — calling `git` directly is simpler, faster
// to develop, and behaves exactly like the user expects (their SSH agent
// config, their hooks, their git config).
package git

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Run executes `git <args>` in dir and returns combined output.
func Run(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

// Clone clones repoURL into dir (parent must exist). Uses --depth 1 by default.
func Clone(repoURL, dir string) error {
	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		return err
	}
	cmd := exec.Command("git", "clone", repoURL, dir)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=1")
	return cmd.Run()
}

// Pull runs `git pull --rebase --autostash` in dir.
func Pull(dir string) error {
	_, err := Run(dir, "pull", "--rebase", "--autostash")
	return err
}

// Status runs `git status --porcelain` and returns the trimmed output.
func Status(dir string) (string, error) {
	out, err := Run(dir, "status", "--porcelain")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// CommitAll stages every change and creates a commit with message.
func CommitAll(dir, message string) error {
	if _, err := Run(dir, "add", "-A"); err != nil {
		return err
	}
	// avoid failing on "nothing to commit"
	if status, _ := Status(dir); status == "" {
		return nil
	}
	if _, err := Run(dir, "commit", "-m", message); err != nil {
		return err
	}
	return nil
}

// Push runs `git push`.
func Push(dir string) error {
	cmd := exec.Command("git", "push")
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=1")
	return cmd.Run()
}

// ConfigUser sets the local user.name + user.email so commits don't fail
// when the user hasn't configured a global identity.
func ConfigUser(dir, name, email string) error {
	if _, err := Run(dir, "config", "user.name", name); err != nil {
		return err
	}
	if _, err := Run(dir, "config", "user.email", email); err != nil {
		return err
	}
	return nil
}
