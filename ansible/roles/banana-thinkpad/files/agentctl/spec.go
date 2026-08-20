package main

import (
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// TaskSpec mirrors the format documented in task-spec.example.yaml. It is
// the audit record of what one run was allowed to do.
type TaskSpec struct {
	Name    string `yaml:"name"`
	Image   string `yaml:"image"`
	Context struct {
		Repo      string   `yaml:"repo"`
		Base      string   `yaml:"base"`
		Prompt    string   `yaml:"prompt"`
		Knowledge []string `yaml:"knowledge"`
	} `yaml:"context"`
	Network struct {
		Allow []string `yaml:"allow"`
	} `yaml:"network"`
	MCP    []string `yaml:"mcp"`
	Limits struct {
		CPUs      int    `yaml:"cpus"`
		Memory    string `yaml:"memory"`
		WallClock string `yaml:"wall_clock"`
	} `yaml:"limits"`
	Outputs struct {
		Keep []string `yaml:"keep"`
	} `yaml:"outputs"`
}

func loadSpec(path string) (*TaskSpec, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read task spec: %w", err)
	}
	var spec TaskSpec
	if err := yaml.Unmarshal(b, &spec); err != nil {
		return nil, fmt.Errorf("parse task spec: %w", err)
	}
	return &spec, nil
}

func (s *TaskSpec) wallClock() time.Duration {
	d, _ := time.ParseDuration(s.Limits.WallClock)
	return d
}

func (s *TaskSpec) validate(cfg *Config) error {
	if s.Name == "" {
		return fmt.Errorf("name is required")
	}
	if s.Image == "" {
		return fmt.Errorf("image is required")
	}
	if s.Context.Repo == "" {
		return fmt.Errorf("context.repo is required")
	}
	if s.Context.Base == "" {
		return fmt.Errorf("context.base is required")
	}
	if s.Context.Prompt == "" {
		return fmt.Errorf("context.prompt is required")
	}
	if _, err := os.Stat(s.Context.Prompt); err != nil {
		return fmt.Errorf("context.prompt %q: %w", s.Context.Prompt, err)
	}
	for _, k := range s.Context.Knowledge {
		if _, err := os.Stat(k); err != nil {
			return fmt.Errorf("context.knowledge %q: %w", k, err)
		}
	}
	for _, m := range s.MCP {
		if _, ok := cfg.MCPPorts[m]; !ok {
			return fmt.Errorf("mcp server %q is not one this host runs", m)
		}
	}
	if s.Limits.CPUs <= 0 {
		return fmt.Errorf("limits.cpus must be positive")
	}
	if s.Limits.Memory == "" {
		return fmt.Errorf("limits.memory is required")
	}
	if s.wallClock() <= 0 {
		return fmt.Errorf("limits.wall_clock %q is invalid", s.Limits.WallClock)
	}
	return nil
}
