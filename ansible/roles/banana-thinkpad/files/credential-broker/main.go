// credential-broker holds the real Anthropic API key and is the only
// component allowed to see it. It listens on the agent bridge, accepts
// requests carrying a per-run token, and forwards them to api.anthropic.com
// through Squid with the real key attached. The real key never reaches a
// microVM.
package main

import (
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	listenAddr   = "10.88.0.1:8081"
	tokensDir    = "/srv/agent/etc/broker-tokens"
	apiKeyFile   = "/srv/agent/etc/anthropic_api_key"
	logFile      = "/srv/agent/log/broker.log"
	squidProxy   = "http://127.0.0.1:3128"
	upstreamHost = "https://api.anthropic.com"
)

func main() {
	logf, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("open log file: %v", err)
	}
	defer logf.Close()
	logger := log.New(logf, "", log.LstdFlags)

	apiKey, err := readAPIKey()
	if err != nil {
		log.Fatalf("read api key: %v", err)
	}

	proxyURL, err := url.Parse(squidProxy)
	if err != nil {
		log.Fatalf("parse squid proxy url: %v", err)
	}

	client := &http.Client{
		Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)},
		Timeout:   60 * time.Second,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		handle(w, r, client, apiKey, logger)
	})

	log.Printf("credential broker listening on %s", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

func readAPIKey() (string, error) {
	b, err := os.ReadFile(apiKeyFile)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

// runIDForToken resolves a per-run token to the run id that owns it.
// agentctl registers a token by writing a file named after the token,
// containing the run id, under tokensDir; it revokes the token by removing
// that file. filepath.Base strips any path components so a token value
// cannot be used to read outside tokensDir.
func runIDForToken(token string) (string, bool) {
	if token == "" {
		return "", false
	}
	path := filepath.Join(tokensDir, filepath.Base(token))
	b, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(string(b)), true
}

func handle(w http.ResponseWriter, r *http.Request, client *http.Client, realKey string, logger *log.Logger) {
	token := r.Header.Get("x-api-key")
	runID, ok := runIDForToken(token)
	if !ok {
		logger.Printf("run=- status=401 path=%s reason=invalid-or-missing-token", r.URL.Path)
		http.Error(w, "invalid or missing run token", http.StatusUnauthorized)
		return
	}

	upstreamURL := upstreamHost + r.URL.Path
	if r.URL.RawQuery != "" {
		upstreamURL += "?" + r.URL.RawQuery
	}

	req, err := http.NewRequest(r.Method, upstreamURL, r.Body)
	if err != nil {
		logger.Printf("run=%s status=500 path=%s reason=build-request-failed", runID, r.URL.Path)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	req.Header = r.Header.Clone()
	req.Header.Set("x-api-key", realKey)
	req.ContentLength = r.ContentLength

	resp, err := client.Do(req)
	if err != nil {
		logger.Printf("run=%s status=502 path=%s reason=%v", runID, r.URL.Path, err)
		http.Error(w, "upstream request failed", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)

	logger.Printf("run=%s status=%d path=%s", runID, resp.StatusCode, r.URL.Path)
}
