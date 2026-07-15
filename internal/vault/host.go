// Package vault defines the host data model and TOML parsing.
//
// The on-disk format is intentionally simple and grep-friendly:
//
//	[hosts.<alias>]
//	user = "deploy"
//	host = "10.0.1.10"
//	port = 22
//	desc = "Frontend production"
//	tags = ["prod", "web", "critical"]
//
// One file = one source of truth = git tracked = synced everywhere.
package vault

import (
	"fmt"
	"sort"
	"strings"
)

// Host is one SSH target.
type Host struct {
	Alias string   `toml:"-"`
	User  string   `toml:"user"`
	Host  string   `toml:"host"`
	Port  int      `toml:"port"`
	Desc  string   `toml:"desc"`
	Tags  []string `toml:"tags"`
}

// Target returns user@host[:port] for display and for building the ssh argv.
func (h Host) Target() string {
	hp := h.Host
	if h.Port != 0 && h.Port != 22 {
		hp = fmt.Sprintf("%s:%d", h.Host, h.Port)
	}
	if h.User != "" {
		return h.User + "@" + hp
	}
	return hp
}

// SSHArg returns the ssh destination: user@host (never with a :port suffix).
//
// The port is passed separately via `ssh -p`. It must NOT appear here: OpenSSH
// treats a "host:port" string in a bare (non-URI) destination as a literal
// hostname, so `ssh -p 2222 user@host:2222` fails with "Could not resolve
// hostname host:2222". Target() keeps the :port form for display only.
func (h Host) SSHArg() string {
	if h.User != "" {
		return h.User + "@" + h.Host
	}
	return h.Host
}

// Match is a case-insensitive substring match against the fuzzy filter.
func (h Host) Match(query string) bool {
	q := strings.ToLower(query)
	if q == "" {
		return true
	}
	hay := strings.ToLower(strings.Join([]string{
		h.Alias, h.Host, h.User, h.Desc, strings.Join(h.Tags, " "),
	}, " "))
	return strings.Contains(hay, q)
}

// File is the contents of hosts.toml.
type File struct {
	Hosts map[string]Host `toml:"hosts"`
}

// New returns an empty File.
func New() *File {
	return &File{Hosts: map[string]Host{}}
}

// List returns the hosts sorted by alias.
func (f *File) List() []Host {
	out := make([]Host, 0, len(f.Hosts))
	for alias, h := range f.Hosts {
		h.Alias = alias
		out = append(out, h)
	}
	sort.Slice(out, func(i, j int) bool {
		return strings.ToLower(out[i].Alias) < strings.ToLower(out[j].Alias)
	})
	return out
}

// Find looks up a host by alias (case-insensitive).
func (f *File) Find(alias string) (Host, bool) {
	for a, h := range f.Hosts {
		if strings.EqualFold(a, alias) {
			h.Alias = a
			return h, true
		}
	}
	return Host{}, false
}

// Upsert adds or updates a host entry.
func (f *File) Upsert(h Host) {
	if h.Alias == "" {
		return
	}
	if h.Port == 0 {
		h.Port = 22
	}
	f.Hosts[h.Alias] = h
}

// Delete removes a host by alias (case-insensitive, matching Find/connect).
func (f *File) Delete(alias string) bool {
	for a := range f.Hosts {
		if strings.EqualFold(a, alias) {
			delete(f.Hosts, a)
			return true
		}
	}
	return false
}
