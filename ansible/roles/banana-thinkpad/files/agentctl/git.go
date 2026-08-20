package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func git(dir string, args ...string) error {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("git %v: %w: %s", args, err, out)
	}
	return nil
}

func (r *Run) projectMirror() string {
	return filepath.Join(r.Cfg.GitMirrorDir, r.Spec.Context.Repo+".git")
}

func (r *Run) remoteRepo() string {
	return r.path("remote.git")
}

// updateMirror fetches the canonical project mirror up to date. The mirror
// itself must already exist - "keep a bare mirror of each project" is
// ongoing operator maintenance, not something a run creates from nothing.
func (r *Run) updateMirror() error {
	mirror := r.projectMirror()
	if _, err := os.Stat(mirror); err != nil {
		return fmt.Errorf("project mirror %q does not exist - bootstrap it first with: git clone --mirror <url> %s", mirror, mirror)
	}
	return git(mirror, "remote", "update")
}

func (r *Run) createPerRunRepo() error {
	if err := git("", "clone", "--mirror", r.projectMirror(), r.remoteRepo()); err != nil {
		return err
	}
	if err := git(r.remoteRepo(), "config", "http.receivepack", "true"); err != nil {
		return err
	}
	return r.writeUpdateHook()
}

// writeUpdateHook installs the ref restriction described in the spec: this
// run may push only to its own agent/<run-id> branch. The hook runs on the
// host, outside the sandbox, under a different user - the agent cannot
// change it or bypass it.
func (r *Run) writeUpdateHook() error {
	hook := fmt.Sprintf(`#!/bin/sh
# hooks/update - args: refname old new
case "$1" in
  refs/heads/%s) exit 0 ;;
  *) echo "denied: this run may write only refs/heads/%s" >&2
     exit 1 ;;
esac
`, r.branch(), r.branch())
	path := filepath.Join(r.remoteRepo(), "hooks", "update")
	if err := os.WriteFile(path, []byte(hook), 0755); err != nil {
		return fmt.Errorf("write update hook: %w", err)
	}
	return nil
}

// cloneWorkspace clones from the per-run repo (not the project mirror)
// because that per-run repo, served over HTTP, is what the agent inside the
// microVM must push to. --reference against the project mirror keeps the
// clone fast even for a large repository.
func (r *Run) cloneWorkspace() error {
	ws := r.path("workspace")
	if err := git("", "clone", "--reference", r.projectMirror(), "--branch", r.Spec.Context.Base, r.remoteRepo(), ws); err != nil {
		return err
	}
	// The clone's origin URL is a local host path, meaningless inside the
	// microVM. Point it at the HTTP remote the guest can actually reach.
	remoteURL := fmt.Sprintf("http://%s:%d/%s/remote.git", r.Cfg.BridgeGateway, r.Cfg.GitPort, r.ID)
	if err := git(ws, "remote", "set-url", "origin", remoteURL); err != nil {
		return err
	}
	return git(ws, "checkout", "-b", r.branch())
}

// fetchBranchIntoMirror pulls whatever the agent pushed back into the
// project mirror for the operator to review. main is never touched - the
// agent only ever had permission to push its own branch.
func (r *Run) fetchBranchIntoMirror() error {
	refspec := fmt.Sprintf("refs/heads/%s:refs/heads/%s", r.branch(), r.branch())
	return git(r.projectMirror(), "fetch", r.remoteRepo(), refspec)
}
