package main

import (
	"encoding/json"
	"fmt"
	"os"
)

// Config is agentctl's own view of the host infrastructure Ansible
// deployed - bridge address, service ports, well-known paths. Reading it
// from a file instead of hardcoding these values keeps the ansible role's
// vars/main.yml the single source of truth.
type Config struct {
	BridgeGateway      string         `json:"bridge_gateway"`
	BridgeSubnet       string         `json:"bridge_subnet"`
	SquidPort          int            `json:"squid_port"`
	BrokerPort         int            `json:"broker_port"`
	GitPort            int            `json:"git_port"`
	MCPPorts           map[string]int `json:"mcp_ports"`
	RunsDir            string         `json:"runs_dir"`
	GitMirrorDir       string         `json:"git_mirror_dir"`
	BrokerTokensDir    string         `json:"broker_tokens_dir"`
	AllowedDomainsFile string         `json:"allowed_domains_file"`
	SquidAccessLog     string         `json:"squid_access_log"`
	MaxConcurrentRuns  int            `json:"max_concurrent_runs"`
}

const configPath = "/srv/agent/etc/agentctl-config.json"

func loadConfig() (*Config, error) {
	b, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("read agentctl config: %w", err)
	}
	var cfg Config
	if err := json.Unmarshal(b, &cfg); err != nil {
		return nil, fmt.Errorf("parse agentctl config: %w", err)
	}
	return &cfg, nil
}
