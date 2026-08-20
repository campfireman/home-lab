// agentctl carries one task spec through a single microVM run: it is a
// sequence of steps, not a daemon. Build and destroy the run, nothing more.
package main

import (
	"fmt"
	"log"
	"os"
	"time"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: agentctl <task-spec.yaml>")
		os.Exit(1)
	}

	cfg, err := loadConfig()
	fatalIf(err)

	spec, err := loadSpec(os.Args[1])
	fatalIf(err)
	fatalIf(spec.validate(cfg))

	run := newRun(generateRunID(), spec, cfg)
	log.Printf("run %s: starting %q", run.ID, spec.Name)
	fatalIf(os.MkdirAll(run.Dir, 0755))

	log.Printf("run %s: updating project mirror", run.ID)
	fatalIf(run.updateMirror())

	log.Printf("run %s: creating per-run repo with ref-restricted push", run.ID)
	fatalIf(run.createPerRunRepo())

	log.Printf("run %s: cloning workspace onto agent/%s", run.ID, run.ID)
	fatalIf(run.cloneWorkspace())

	log.Printf("run %s: copying prompt and knowledge into context", run.ID)
	fatalIf(run.copyContext())
	fatalIf(os.MkdirAll(run.path("out"), 0755))

	token, err := generateToken()
	fatalIf(err)
	fatalIf(run.registerBrokerToken(token))

	log.Printf("run %s: opening network access", run.ID)
	added, err := addAllowedDomains(cfg.AllowedDomainsFile, spec.Network.Allow)
	fatalIf(err)
	fatalIf(reloadSquid())
	fatalIf(run.openMCPPorts())

	log.Printf("run %s: starting microVM (image %s, limit %s)", run.ID, spec.Image, spec.Limits.WallClock)
	start := time.Now()
	exitCode, runErr := run.runContainer(token)
	duration := time.Since(start)
	if runErr != nil {
		log.Printf("run %s: %v", run.ID, runErr)
	}

	// Teardown is best-effort from here on: one failed cleanup step must
	// not skip the rest, since each closes a different door.
	log.Printf("run %s: closing network access", run.ID)
	run.closeMCPPorts(log.Printf)
	if err := run.revokeBrokerToken(token); err != nil {
		log.Printf("run %s: revoke token: %v", run.ID, err)
	}
	if err := removeAllowedDomains(cfg.AllowedDomainsFile, added); err != nil {
		log.Printf("run %s: remove allowed domains: %v", run.ID, err)
	}
	if err := reloadSquid(); err != nil {
		log.Printf("run %s: reload squid: %v", run.ID, err)
	}

	log.Printf("run %s: fetching agent branch into project mirror", run.ID)
	if err := run.fetchBranchIntoMirror(); err != nil {
		log.Printf("run %s: fetch branch: %v", run.ID, err)
	}

	allowed, denied := countProxyRequests(cfg.SquidAccessLog, start, time.Now())
	fatalIf(run.writeSummary(exitCode, duration, allowed, denied))

	log.Printf("run %s: done, exit=%d duration=%s branch=%s allowed=%d denied=%d",
		run.ID, exitCode, duration.Round(time.Second), run.branch(), allowed, denied)
}

func fatalIf(err error) {
	if err != nil {
		log.Fatal(err)
	}
}
