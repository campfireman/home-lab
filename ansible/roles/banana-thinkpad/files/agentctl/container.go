package main

import (
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

func (r *Run) containerName() string {
	return "agent-" + r.ID
}

// countActiveRuns counts running containers named agent-* - agentctl is a
// sequence of steps, not a daemon, so this is the only shared state across
// independent invocations that a concurrency cap can check against.
func countActiveRuns() (int, error) {
	out, err := exec.Command("nerdctl", "ps", "--format", "{{.Names}}").Output()
	if err != nil {
		return 0, fmt.Errorf("list running containers: %w", err)
	}
	n := 0
	for _, name := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.HasPrefix(name, "agent-") {
			n++
		}
	}
	return n, nil
}

func checkConcurrencyLimit(cfg *Config) error {
	if cfg.MaxConcurrentRuns <= 0 {
		return nil
	}
	active, err := countActiveRuns()
	if err != nil {
		return err
	}
	if active >= cfg.MaxConcurrentRuns {
		return fmt.Errorf("refusing to start: %d runs already active (max %d)", active, cfg.MaxConcurrentRuns)
	}
	return nil
}

func (r *Run) nerdctlArgs(token string) []string {
	return []string{
		"run", "-d",
		"--name", r.containerName(),
		"--runtime", "io.containerd.kata-clh.v2",
		"--network", "agentbr0",
		"--cpus", strconv.Itoa(r.Spec.Limits.CPUs),
		"--memory", r.Spec.Limits.Memory,
		"-v", r.path("workspace") + ":/workspace",
		"-v", r.path("context") + ":/context:ro",
		"-v", r.path("out") + ":/out",
		"-e", fmt.Sprintf("HTTP_PROXY=http://%s:%d", r.Cfg.BridgeGateway, r.Cfg.SquidPort),
		"-e", fmt.Sprintf("HTTPS_PROXY=http://%s:%d", r.Cfg.BridgeGateway, r.Cfg.SquidPort),
		"-e", fmt.Sprintf("ANTHROPIC_BASE_URL=http://%s:%d", r.Cfg.BridgeGateway, r.Cfg.BrokerPort),
		"-e", "ANTHROPIC_API_KEY=" + token,
		r.Spec.Image,
		"/usr/local/bin/run-agent",
	}
}

// runContainer starts the microVM detached (so a wall-clock timeout can
// stop it explicitly rather than relying on signal propagation through the
// nerdctl client process) and waits for it to exit or for the wall-clock
// limit to expire, whichever comes first.
func (r *Run) runContainer(token string) (exitCode int, err error) {
	if out, err := exec.Command("nerdctl", r.nerdctlArgs(token)...).CombinedOutput(); err != nil {
		return -1, fmt.Errorf("start container: %w: %s", err, out)
	}
	defer exec.Command("nerdctl", "rm", "-f", r.containerName()).Run()

	done := make(chan int, 1)
	go func() {
		out, err := exec.Command("nerdctl", "wait", r.containerName()).Output()
		if err != nil {
			done <- -1
			return
		}
		code, _ := strconv.Atoi(strings.TrimSpace(string(out)))
		done <- code
	}()

	select {
	case exitCode = <-done:
		return exitCode, nil
	case <-time.After(r.Spec.wallClock()):
		exec.Command("nerdctl", "stop", r.containerName()).Run()
		return <-done, fmt.Errorf("wall-clock limit (%s) exceeded, container stopped", r.Spec.Limits.WallClock)
	}
}
