package main

import (
	"bufio"
	"encoding/json"
	"os"
	"strconv"
	"strings"
	"time"
)

type Summary struct {
	RunID       string  `json:"run_id"`
	Branch      string  `json:"branch"`
	ExitCode    int     `json:"exit_code"`
	DurationSec float64 `json:"duration_seconds"`
	Allowed     int     `json:"proxy_requests_allowed"`
	Denied      int     `json:"proxy_requests_denied"`
}

// countProxyRequests scans the squid access log for lines timestamped
// within [start, end) and tallies allowed (TCP_TUNNEL) vs denied
// (TCP_DENIED) requests. This is a time-window count, not attributed to a
// specific guest IP, so a second run active in the same window shows up in
// both summaries - an accepted simplification for a single-operator host.
func countProxyRequests(path string, start, end time.Time) (allowed, denied int) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 4 {
			continue
		}
		sec, err := strconv.ParseFloat(fields[0], 64)
		if err != nil {
			continue
		}
		ts := time.Unix(int64(sec), 0)
		if ts.Before(start) || !ts.Before(end) {
			continue
		}
		switch {
		case strings.HasPrefix(fields[3], "TCP_TUNNEL"):
			allowed++
		case strings.HasPrefix(fields[3], "TCP_DENIED"):
			denied++
		}
	}
	return allowed, denied
}

func (r *Run) writeSummary(exitCode int, duration time.Duration, allowed, denied int) error {
	s := Summary{
		RunID:       r.ID,
		Branch:      r.branch(),
		ExitCode:    exitCode,
		DurationSec: duration.Seconds(),
		Allowed:     allowed,
		Denied:      denied,
	}
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(r.path("summary.json"), b, 0644)
}
