package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"time"
)

// Run holds everything needed to carry one task spec through a single
// microVM run: its generated id, its directory under runs_dir, and the
// spec/config it was built from.
type Run struct {
	ID   string
	Dir  string
	Spec *TaskSpec
	Cfg  *Config
}

func generateRunID() string {
	b := make([]byte, 4)
	rand.Read(b)
	return fmt.Sprintf("%d-%s", time.Now().Unix(), hex.EncodeToString(b))
}

func newRun(id string, spec *TaskSpec, cfg *Config) *Run {
	return &Run{
		ID:   id,
		Dir:  filepath.Join(cfg.RunsDir, id),
		Spec: spec,
		Cfg:  cfg,
	}
}

func (r *Run) path(parts ...string) string {
	return filepath.Join(append([]string{r.Dir}, parts...)...)
}

func (r *Run) branch() string {
	return "agent/" + r.ID
}
