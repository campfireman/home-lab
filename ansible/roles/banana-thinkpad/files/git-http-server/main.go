// git-http-server serves per-run bare git repositories under /srv/runs over
// the smart HTTP protocol via git-http-backend. It performs no
// authentication of its own - the nftables rules on the agent bridge are
// what limit who can reach this port, and each repo's own "update" hook
// (written per-run, outside the sandbox) is what limits which ref may be
// pushed.
package main

import (
	"log"
	"net/http"
	"net/http/cgi"
)

const listenAddr = "10.88.0.1:3000"

func main() {
	handler := &cgi.Handler{
		Path: "/usr/lib/git-core/git-http-backend",
		Root: "",
		Env: []string{
			"GIT_PROJECT_ROOT=/srv/runs",
			"GIT_HTTP_EXPORT_ALL=1",
			"PATH=/usr/bin:/bin:/usr/local/bin",
		},
	}
	log.Printf("git http backend listening on %s", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, handler))
}
