// Package store handles reading and writing the hosts.toml file on disk.
package store

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"

	"github.com/user/sshvault/internal/vault"
)

// DefaultPath returns the conventional location of hosts.toml.
func DefaultPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".ssh", "vault", "hosts.toml"), nil
}

// Load reads and parses the hosts file at path. Missing file => empty File.
func Load(path string) (*vault.File, error) {
	if path == "" {
		var err error
		path, err = DefaultPath()
		if err != nil {
			return nil, err
		}
	}
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return vault.New(), nil
		}
		return nil, err
	}
	defer f.Close()

	var file vault.File
	if _, err := toml.NewDecoder(f).Decode(&file); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if file.Hosts == nil {
		file.Hosts = map[string]vault.Host{}
	}
	return &file, nil
}

// Save writes the file in canonical form (sorted keys, 2-space indent).
func Save(path string, file *vault.File) error {
	if path == "" {
		p, err := DefaultPath()
		if err != nil {
			return err
		}
		path = p
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	enc := toml.NewEncoder(f)
	enc.Indent = "  "
	if err := enc.Encode(file); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
