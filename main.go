// sshvault — minimal TUI SSH launcher with hosts synced via a git repo.
//
// Commands:
//
//	sshvault                       open the TUI host picker
//	sshvault <alias>               connect directly to a host
//	sshvault list                  print all hosts (script-friendly)
//	sshvault add                   add a new host (interactive prompts)
//	sshvault remove <alias>        remove a host
//	sshvault edit                  open hosts.toml in $EDITOR
//	sshvault pull                  git pull the vault repo
//	sshvault push [msg]            git add+commit+push the vault repo
//	sshvault path                  print the path to hosts.toml
//	sshvault version
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/user/sshvault/internal/git"
	"github.com/user/sshvault/internal/run"
	"github.com/user/sshvault/internal/store"
	"github.com/user/sshvault/internal/ui"
	"github.com/user/sshvault/internal/vault"
)

const version = "1.0.0"

func main() {
	flag.Usage = usage
	flag.Parse()
	args := flag.Args()

	if len(args) == 0 {
		args = []string{"menu"}
	}

	cmd := args[0]
	rest := args[1:]

	switch cmd {
	case "version", "--version", "-v":
		fmt.Println("sshvault", version)

	case "path":
		p, _ := store.DefaultPath()
		fmt.Println(p)

	case "list", "ls":
		hosts, err := loadList()
		if err != nil {
			die("load: %v", err)
		}
		for _, h := range hosts {
			tags := ""
			if len(h.Tags) > 0 {
				tags = "\t#" + strings.Join(h.Tags, " #")
			}
			fmt.Printf("%s\t%s\t%s%s\n", h.Alias, h.Target(), h.Desc, tags)
		}

	case "pull":
		dir, _ := storeDir()
		if err := git.Pull(dir); err != nil {
			die("pull: %v", err)
		}
		fmt.Println("✓ vault up to date")

	case "push":
		dir, _ := storeDir()
		msg := "update vault"
		if len(rest) > 0 {
			msg = strings.Join(rest, " ")
		}
		if err := git.CommitAll(dir, msg); err != nil {
			die("commit: %v", err)
		}
		if err := git.Push(dir); err != nil {
			die("push: %v", err)
		}
		fmt.Println("✓ vault pushed")

	case "add":
		if err := addHost(); err != nil {
			die("add: %v", err)
		}

	case "remove", "rm":
		if len(rest) == 0 {
			die("usage: sshvault remove <alias>")
		}
		if err := removeHost(rest[0]); err != nil {
			die("remove: %v", err)
		}

	case "edit":
		if err := editHosts(); err != nil {
			die("edit: %v", err)
		}

	case "menu", "tui", "ui":
		hosts, err := loadList()
		if err != nil {
			die("load: %v", err)
		}
		picked, err := ui.Run(hosts)
		if err != nil {
			die("ui: %v", err)
		}
		if picked == nil {
			return
		}
		if err := run.Connect(*picked); err != nil {
			die("connect: %v", err)
		}

	default:
		// Treat first arg as alias
		hosts, err := loadList()
		if err != nil {
			die("load: %v", err)
		}
		h, ok := hostsFile(hosts).Find(cmd)
		if !ok {
			die("host %q not found — run `sshvault list`", cmd)
		}
		if err := run.Connect(h); err != nil {
			die("connect: %v", err)
		}
	}
}

// ─── helpers ──────────────────────────────────────

func loadList() ([]vault.Host, error) {
	f, err := loadFile()
	if err != nil {
		return nil, err
	}
	return f.List(), nil
}

func loadFile() (*vault.File, error) {
	p, err := store.DefaultPath()
	if err != nil {
		return nil, err
	}
	return store.Load(p)
}

func saveFile(f *vault.File) error {
	p, err := store.DefaultPath()
	if err != nil {
		return err
	}
	return store.Save(p, f)
}

// hostsFile turns a slice back into a File (for find-by-alias).
func hostsFile(hosts []vault.Host) *vault.File {
	f := vault.New()
	for _, h := range hosts {
		f.Hosts[h.Alias] = h
	}
	return f
}

func storeDir() (string, error) {
	p, err := store.DefaultPath()
	if err != nil {
		return "", err
	}
	return filepath.Dir(p), nil
}

func addHost() error {
	f, err := loadFile()
	if err != nil {
		return err
	}
	reader := bufio.NewReader(os.Stdin)
	prompt := func(q string) string {
		fmt.Print(q)
		s, _ := reader.ReadString('\n')
		return strings.TrimSpace(s)
	}

	alias := prompt("alias (e.g. prod-web): ")
	if alias == "" {
		return fmt.Errorf("alias required")
	}
	user := prompt("user (e.g. deploy) [root]: ")
	if user == "" {
		user = "root"
	}
	host := prompt("host (e.g. 10.0.1.10): ")
	if host == "" {
		return fmt.Errorf("host required")
	}
	port := prompt("port [22]: ")
	desc := prompt("description: ")
	tagsRaw := prompt("tags (comma separated): ")

	var tags []string
	for _, t := range strings.Split(tagsRaw, ",") {
		t = strings.TrimSpace(t)
		if t != "" {
			tags = append(tags, t)
		}
	}

	p := 0
	if port != "" {
		fmt.Sscanf(port, "%d", &p)
	}

	f.Upsert(vault.Host{
		Alias: alias, User: user, Host: host, Port: p,
		Desc: desc, Tags: tags,
	})
	if err := saveFile(f); err != nil {
		return err
	}
	fmt.Printf("✓ added %s — run `sshvault push` to sync\n", alias)
	return nil
}

func removeHost(alias string) error {
	f, err := loadFile()
	if err != nil {
		return err
	}
	if !f.Delete(alias) {
		return fmt.Errorf("alias %q not found", alias)
	}
	if err := saveFile(f); err != nil {
		return err
	}
	fmt.Printf("✓ removed %s — run `sshvault push` to sync\n", alias)
	return nil
}

func editHosts() error {
	p, err := store.DefaultPath()
	if err != nil {
		return err
	}
	editor := os.Getenv("EDITOR")
	if editor == "" {
		if runtime.GOOS == "windows" {
			editor = "notepad"
		} else {
			editor = "vi"
		}
	}
	cmd := exec.Command(editor, p)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func die(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, "[ sshvault ] error: "+format+"\n", a...)
	os.Exit(1)
}

func usage() {
	fmt.Fprintf(os.Stderr, `sshvault v%s — TUI SSH launcher synced via git

usage:
  %s [command] [args]

commands:
  (no args)         open TUI host picker
  <alias>           connect to host
  list              list all hosts
  add               add a new host (interactive)
  remove <alias>    remove a host
  edit              open hosts.toml in $EDITOR
  pull              git pull the vault
  push [msg]        git add+commit+push
  path              print hosts.toml path
  version           print version
`, version, "sshvault")
}
