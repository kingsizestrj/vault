package vault

import (
	"testing"
)

func TestHost_Target(t *testing.T) {
	cases := []struct {
		h    Host
		want string
	}{
		{Host{Alias: "x", User: "deploy", Host: "10.0.1.10"}, "deploy@10.0.1.10"},
		{Host{Alias: "x", User: "deploy", Host: "10.0.1.10", Port: 22}, "deploy@10.0.1.10"},
		{Host{Alias: "x", User: "deploy", Host: "10.0.1.10", Port: 2222}, "deploy@10.0.1.10:2222"},
		{Host{Alias: "x", Host: "h"}, "h"},
		{Host{Alias: "x", User: "u", Host: "h", Port: 5000}, "u@h:5000"},
	}
	for _, c := range cases {
		if got := c.h.Target(); got != c.want {
			t.Errorf("Target() = %q, want %q", got, c.want)
		}
	}
}

func TestHost_Match(t *testing.T) {
	h := Host{
		Alias: "prod-web",
		Host:  "10.0.1.10",
		User:  "deploy",
		Desc:  "Frontend production",
		Tags:  []string{"prod", "web"},
	}
	cases := []struct {
		q    string
		want bool
	}{
		{"", true},
		{"prod", true},
		{"PROD", true},
		{"10.0.1", true},
		{"deploy", true},
		{"frontend", true},
		{"staging", false},
	}
	for _, c := range cases {
		if got := h.Match(c.q); got != c.want {
			t.Errorf("Match(%q) = %v, want %v", c.q, got, c.want)
		}
	}
}

func TestFile_Upsert(t *testing.T) {
	f := New()
	f.Upsert(Host{Alias: "a", User: "u", Host: "h"})
	f.Upsert(Host{Alias: "b", User: "u", Host: "h", Port: 2222})
	if len(f.Hosts) != 2 {
		t.Errorf("expected 2 hosts, got %d", len(f.Hosts))
	}
	if f.Hosts["a"].Port != 22 {
		t.Errorf("default port should be 22, got %d", f.Hosts["a"].Port)
	}
	if f.Hosts["b"].Port != 2222 {
		t.Errorf("explicit port lost, got %d", f.Hosts["b"].Port)
	}
}

func TestFile_Delete(t *testing.T) {
	f := New()
	f.Upsert(Host{Alias: "a", Host: "h"})
	if !f.Delete("a") {
		t.Error("expected delete to succeed")
	}
	if _, ok := f.Hosts["a"]; ok {
		t.Error("alias should be gone")
	}
	if f.Delete("a") {
		t.Error("second delete should fail")
	}
}

func TestFile_Find(t *testing.T) {
	f := New()
	f.Upsert(Host{Alias: "prod-web", Host: "10.0.1.10"})
	if _, ok := f.Find("prod-web"); !ok {
		t.Error("should find by exact alias")
	}
	if _, ok := f.Find("PROD-WEB"); !ok {
		t.Error("should find case-insensitively")
	}
	if _, ok := f.Find("nope"); ok {
		t.Error("should not find missing")
	}
}

func TestFile_List_Sorted(t *testing.T) {
	f := New()
	f.Upsert(Host{Alias: "zeta", Host: "h"})
	f.Upsert(Host{Alias: "alpha", Host: "h"})
	f.Upsert(Host{Alias: "Beta", Host: "h"})
	got := f.List()
	if got[0].Alias != "alpha" || got[1].Alias != "Beta" || got[2].Alias != "zeta" {
		t.Errorf("not sorted case-insensitively: %v", got)
	}
}
