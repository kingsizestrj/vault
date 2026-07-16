// Package ui renders the host picker.
package ui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/user/sshvault/internal/vault"
)

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#FAFAFA")).
			Background(lipgloss.Color("#7D56F4")).
			Padding(0, 1)

	aliasStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#7D56FF"))

	targetStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#04B575"))

	descStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#888888"))

	tagStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#F7768E"))

	cursorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#EE6FF8")).
			SetString("▶ ")

	helpStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#626262"))

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#444444"))
)

type model struct {
	hosts    []vault.Host
	filtered []vault.Host
	cursor   int
	query    string
	choice   *vault.Host
	quitting bool
	action   string // verb shown in the footer/title, e.g. "connect" or "copy key"
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc", "q":
			m.quitting = true
			return m, tea.Quit
		case "enter":
			if len(m.filtered) > 0 {
				h := m.filtered[m.cursor]
				m.choice = &h
			}
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.filtered)-1 {
				m.cursor++
			}
		case "backspace":
			if len(m.query) > 0 {
				m.query = m.query[:len(m.query)-1]
				m.applyFilter()
			}
		default:
			if len(msg.Runes) == 1 {
				r := msg.Runes[0]
				if r >= 32 && r < 127 {
					m.query += string(r)
					m.applyFilter()
				}
			}
		}
	}
	return m, nil
}

func (m *model) applyFilter() {
	if m.query == "" {
		m.filtered = m.hosts
		m.cursor = 0
		return
	}
	// A fresh slice — NOT m.hosts[:0], which shares m.hosts' backing array and
	// would overwrite the master list in place as we append matches.
	out := make([]vault.Host, 0, len(m.hosts))
	for _, h := range m.hosts {
		if h.Match(m.query) {
			out = append(out, h)
		}
	}
	m.filtered = out
	if m.cursor >= len(m.filtered) {
		m.cursor = len(m.filtered) - 1
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
}

func (m model) View() string {
	if m.quitting {
		return ""
	}
	var b strings.Builder
	b.WriteString(titleStyle.Render(" sshvault "))
	b.WriteString("  ")
	status := fmt.Sprintf("%d hosts", len(m.hosts))
	if m.action != "" && m.action != "connect" {
		status += " · " + m.action + " mode"
	}
	b.WriteString(dimStyle.Render(status))
	b.WriteString("\n\n")

	if m.query == "" {
		b.WriteString("  " + dimStyle.Render("type to filter…") + "\n\n")
	} else {
		b.WriteString("  " + aliasStyle.Render("/"+m.query) + "\n\n")
	}

	if len(m.filtered) == 0 {
		b.WriteString(dimStyle.Render("  (no matches)\n"))
	} else {
		max := len(m.filtered)
		if max > 14 {
			max = 14
		}
		start := 0
		if m.cursor >= max {
			start = m.cursor - max + 1
		}
		end := start + max
		if end > len(m.filtered) {
			end = len(m.filtered)
		}
		for i := start; i < end; i++ {
			h := m.filtered[i]
			cursor := "  "
			nameStyle := aliasStyle
			tgtStyle := dimStyle
			if i == m.cursor {
				cursor = cursorStyle.Render()
				tgtStyle = targetStyle
			}
			b.WriteString(cursor)
			b.WriteString(nameStyle.Render(fmt.Sprintf("%-20s", h.Alias)))
			b.WriteString("  ")
			b.WriteString(tgtStyle.Render(h.Target()))
			if h.Desc != "" {
				b.WriteString("  ")
				b.WriteString(descStyle.Render(h.Desc))
			}
			if len(h.Tags) > 0 {
				b.WriteString("  ")
				b.WriteString(tagStyle.Render("#" + strings.Join(h.Tags, " #")))
			}
			b.WriteString("\n")
		}
		if start > 0 || end < len(m.filtered) {
			b.WriteString(dimStyle.Render(fmt.Sprintf("  …showing %d-%d of %d\n", start+1, end, len(m.filtered))))
		}
	}

	action := m.action
	if action == "" {
		action = "connect"
	}
	b.WriteString("\n")
	b.WriteString(helpStyle.Render(fmt.Sprintf("  ↑↓/jk move · enter %s · type to filter · q quit", action)))
	return b.String()
}

// Run shows the menu and returns the selected host (nil if user quit).
func Run(hosts []vault.Host) (*vault.Host, error) {
	return Pick(hosts, "connect")
}

// Pick shows the menu with a custom action verb (used in the footer/title,
// e.g. "connect" or "copy key") and returns the selected host (nil if the
// user quit).
func Pick(hosts []vault.Host, action string) (*vault.Host, error) {
	if len(hosts) == 0 {
		return nil, fmt.Errorf("no hosts in vault — run `sshvault add` to add one")
	}
	p := tea.NewProgram(model{hosts: hosts, filtered: hosts, action: action})
	final, err := p.Run()
	if err != nil {
		return nil, err
	}
	return final.(model).choice, nil
}
