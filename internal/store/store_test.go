package store

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/user/sshvault/internal/vault"
)

func TestSaveLoad_RoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hosts.toml")

	f := vault.New()
	f.Upsert(vault.Host{Alias: "prod-web", User: "deploy", Host: "10.0.1.10", Desc: "frontend", Tags: []string{"prod", "web"}})
	f.Upsert(vault.Host{Alias: "staging", User: "ubuntu", Host: "stg.example.com", Port: 2222, Desc: "stg"})

	if err := Save(path, f); err != nil {
		t.Fatalf("save: %v", err)
	}

	got, err := Load(path)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(got.Hosts) != 2 {
		t.Fatalf("expected 2, got %d", len(got.Hosts))
	}
	hw := got.Hosts["prod-web"]
	if hw.User != "deploy" || hw.Host != "10.0.1.10" || hw.Desc != "frontend" {
		t.Errorf("prod-web mismatch: %+v", hw)
	}
	if len(hw.Tags) != 2 || hw.Tags[0] != "prod" || hw.Tags[1] != "web" {
		t.Errorf("tags lost: %v", hw.Tags)
	}
	hs := got.Hosts["staging"]
	if hs.Port != 2222 {
		t.Errorf("port lost: %d", hs.Port)
	}
}

func TestLoad_MissingFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nope.toml")
	f, err := Load(path)
	if err != nil {
		t.Fatalf("missing file should not error: %v", err)
	}
	if f == nil || len(f.Hosts) != 0 {
		t.Errorf("expected empty file, got %+v", f)
	}
}

func TestLoad_BadFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "bad.toml")
	if err := os.WriteFile(path, []byte("this is not toml ===="), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Error("expected error on bad toml")
	}
}
