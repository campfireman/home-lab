package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func generateToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (r *Run) registerBrokerToken(token string) error {
	path := filepath.Join(r.Cfg.BrokerTokensDir, token)
	return os.WriteFile(path, []byte(r.ID+"\n"), 0600)
}

func (r *Run) revokeBrokerToken(token string) error {
	path := filepath.Join(r.Cfg.BrokerTokensDir, token)
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func readLines(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		l := strings.TrimSpace(scanner.Text())
		if l != "" {
			lines = append(lines, l)
		}
	}
	return lines, scanner.Err()
}

// addAllowedDomains appends only domains not already present, and returns
// exactly the ones it added. Only those may be safely removed again at
// cleanup - a baseline entry like api.anthropic.com, or a domain another
// concurrent run still needs, is never dropped underneath it.
func addAllowedDomains(path string, allow []string) ([]string, error) {
	existing, err := readLines(path)
	if err != nil {
		return nil, err
	}
	have := map[string]bool{}
	for _, l := range existing {
		have[l] = true
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var added []string
	for _, d := range allow {
		if have[d] {
			continue
		}
		if _, err := fmt.Fprintln(f, d); err != nil {
			return added, err
		}
		added = append(added, d)
		have[d] = true
	}
	return added, nil
}

func removeAllowedDomains(path string, added []string) error {
	if len(added) == 0 {
		return nil
	}
	remove := map[string]bool{}
	for _, d := range added {
		remove[d] = true
	}
	existing, err := readLines(path)
	if err != nil {
		return err
	}
	var kept []string
	for _, l := range existing {
		if !remove[l] {
			kept = append(kept, l)
		}
	}
	return os.WriteFile(path, []byte(strings.Join(kept, "\n")+"\n"), 0644)
}

func reloadSquid() error {
	return exec.Command("systemctl", "reload", "squid").Run()
}

func nftSetAdd(port int) error {
	out, err := exec.Command("nft", "add", "element", "inet", "filter", "mcp_open_ports", fmt.Sprintf("{ %d }", port)).CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft add element: %w: %s", err, out)
	}
	return nil
}

func nftSetDelete(port int) error {
	out, err := exec.Command("nft", "delete", "element", "inet", "filter", "mcp_open_ports", fmt.Sprintf("{ %d }", port)).CombinedOutput()
	if err != nil {
		return fmt.Errorf("nft delete element: %w: %s", err, out)
	}
	return nil
}

func (r *Run) openMCPPorts() error {
	for _, name := range r.Spec.MCP {
		if err := nftSetAdd(r.Cfg.MCPPorts[name]); err != nil {
			return fmt.Errorf("open mcp port for %s: %w", name, err)
		}
	}
	return nil
}

// closeMCPPorts is cleanup - it logs failures but never aborts, so the
// remaining teardown steps (token revoke, domain removal, summary) still
// run even if one port was already gone.
func (r *Run) closeMCPPorts(warn func(string, ...interface{})) {
	for _, name := range r.Spec.MCP {
		if err := nftSetDelete(r.Cfg.MCPPorts[name]); err != nil {
			warn("close mcp port for %s: %v", name, err)
		}
	}
}
