// Command lowcode-web serves the built lowCode-platform SPA and exposes
// health, version and Prometheus-compatible metrics endpoints.
//
// It is intentionally dependency-free so the container image can be built
// FROM scratch without pulling a base image (Docker Hub is unavailable in the
// target lab environment).
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Injected with -ldflags at build time.
var (
	version   = "dev"
	commit    = "unknown"
	buildTime = "unknown"
)

type config struct {
	listenAddr string
	staticDir  string
	appEnv     string
	failReady  bool
	logLevel   slog.Level
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func loadConfig() config {
	level := slog.LevelInfo
	switch strings.ToLower(envOr("LOG_LEVEL", "info")) {
	case "debug":
		level = slog.LevelDebug
	case "warn", "warning":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	}
	failReady, _ := strconv.ParseBool(envOr("FAIL_READY", "false"))
	return config{
		listenAddr: envOr("LISTEN_ADDR", ":8080"),
		staticDir:  envOr("STATIC_DIR", "./static"),
		appEnv:     envOr("APP_ENV", "dev"),
		failReady:  failReady,
		logLevel:   level,
	}
}

type metricKey struct {
	method string
	route  string
	status int
}

type durationStat struct {
	buckets []float64
	counts  []uint64
	sum     float64
	count   uint64
}

type metrics struct {
	mu       sync.Mutex
	requests map[metricKey]uint64
	duration map[string]*durationStat
	started  time.Time
}

var bucketBounds = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10}

func newMetrics() *metrics {
	return &metrics{
		requests: make(map[metricKey]uint64),
		duration: make(map[string]*durationStat),
		started:  time.Now(),
	}
}

func (m *metrics) observe(method, route string, status int, d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests[metricKey{method: method, route: route, status: status}]++
	st := m.duration[route]
	if st == nil {
		st = &durationStat{buckets: bucketBounds, counts: make([]uint64, len(bucketBounds))}
		m.duration[route] = st
	}
	seconds := d.Seconds()
	for i, b := range st.buckets {
		if seconds <= b {
			st.counts[i]++
		}
	}
	st.sum += seconds
	st.count++
}

func escapeLabel(v string) string {
	v = strings.ReplaceAll(v, `\`, `\\`)
	v = strings.ReplaceAll(v, `"`, `\"`)
	v = strings.ReplaceAll(v, "\n", `\n`)
	return v
}

func (m *metrics) render(w http.ResponseWriter) {
	m.mu.Lock()
	defer m.mu.Unlock()

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")

	fmt.Fprintf(w, "# HELP lowcode_build_info Build information for the lowcode web server.\n")
	fmt.Fprintf(w, "# TYPE lowcode_build_info gauge\n")
	fmt.Fprintf(w, "lowcode_build_info{version=%q,commit=%q,env=%q} 1\n", escapeLabel(version), escapeLabel(commit), escapeLabel(envOr("APP_ENV", "dev")))
	fmt.Fprintf(w, "# HELP lowcode_process_start_time_seconds Unix time the process started.\n")
	fmt.Fprintf(w, "# TYPE lowcode_process_start_time_seconds gauge\n")
	fmt.Fprintf(w, "lowcode_process_start_time_seconds %d\n", m.started.Unix())

	fmt.Fprintf(w, "# HELP lowcode_http_requests_total Total HTTP requests handled.\n")
	fmt.Fprintf(w, "# TYPE lowcode_http_requests_total counter\n")
	keys := make([]metricKey, 0, len(m.requests))
	for k := range m.requests {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].route != keys[j].route {
			return keys[i].route < keys[j].route
		}
		if keys[i].method != keys[j].method {
			return keys[i].method < keys[j].method
		}
		return keys[i].status < keys[j].status
	})
	for _, k := range keys {
		fmt.Fprintf(w, "lowcode_http_requests_total{method=%q,route=%q,status=%q} %d\n",
			escapeLabel(k.method), escapeLabel(k.route), strconv.Itoa(k.status), m.requests[k])
	}

	fmt.Fprintf(w, "# HELP lowcode_http_request_duration_seconds HTTP request latency.\n")
	fmt.Fprintf(w, "# TYPE lowcode_http_request_duration_seconds histogram\n")
	routes := make([]string, 0, len(m.duration))
	for route := range m.duration {
		routes = append(routes, route)
	}
	sort.Strings(routes)
	for _, route := range routes {
		st := m.duration[route]
		for i, b := range st.buckets {
			fmt.Fprintf(w, "lowcode_http_request_duration_seconds_bucket{route=%q,le=%q} %d\n",
				escapeLabel(route), strconv.FormatFloat(b, 'g', -1, 64), st.counts[i])
		}
		fmt.Fprintf(w, "lowcode_http_request_duration_seconds_bucket{route=%q,le=\"+Inf\"} %d\n", escapeLabel(route), st.count)
		fmt.Fprintf(w, "lowcode_http_request_duration_seconds_sum{route=%q} %s\n", escapeLabel(route), strconv.FormatFloat(st.sum, 'g', -1, 64))
		fmt.Fprintf(w, "lowcode_http_request_duration_seconds_count{route=%q} %d\n", escapeLabel(route), st.count)
	}
}

func normalizeRoute(p string) string {
	switch p {
	case "/", "/healthz", "/readyz", "/api/version", "/metrics":
		return p
	}
	switch {
	case strings.HasPrefix(p, "/assets/"):
		return "/assets/*"
	case strings.HasPrefix(p, "/api/"):
		return "/api/*"
	default:
		return "other"
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	if r.status == 0 {
		r.status = code
		r.ResponseWriter.WriteHeader(code)
	}
}

func (r *statusRecorder) Write(p []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	n, err := r.ResponseWriter.Write(p)
	r.bytes += n
	return n, err
}

type server struct {
	cfg     config
	log     *slog.Logger
	metrics *metrics
	mux     *http.ServeMux
	static  http.Handler
}

func newServer(cfg config, log *slog.Logger) *server {
	s := &server{
		cfg:     cfg,
		log:     log,
		metrics: newMetrics(),
		static:  http.FileServer(http.Dir(cfg.staticDir)),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", s.handleHealth)
	mux.HandleFunc("/readyz", s.handleReady)
	mux.HandleFunc("/api/version", s.handleVersion)
	mux.HandleFunc("/metrics", s.handleMetrics)
	mux.HandleFunc("/", s.handleStatic)
	s.mux = mux
	return s
}

func (s *server) Handler() http.Handler {
	return s.recoverer(s.instrument(s.mux))
}

func (s *server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				s.log.Error("panic", "method", r.Method, "path", r.URL.Path, "panic", fmt.Sprint(rec))
				http.Error(w, "internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *server) instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		if rec.status == 0 {
			rec.status = http.StatusOK
		}
		route := normalizeRoute(r.URL.Path)
		s.metrics.observe(r.Method, route, rec.status, time.Since(start))
		s.log.Info("http_request",
			"method", r.Method,
			"path", r.URL.Path,
			"route", route,
			"status", rec.status,
			"duration_ms", float64(time.Since(start).Microseconds())/1000.0,
			"bytes", rec.bytes,
			"remote", r.RemoteAddr,
		)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "env": s.cfg.appEnv})
}

func (s *server) handleReady(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if s.cfg.failReady {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not-ready", "reason": "FAIL_READY=true"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready", "env": s.cfg.appEnv})
}

func (s *server) handleVersion(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"version":   envOr("APP_VERSION", version),
		"commit":    envOr("GIT_COMMIT", commit),
		"buildTime": envOr("BUILD_TIME", buildTime),
		"env":       s.cfg.appEnv,
		"goVersion": runtime.Version(),
	})
}

func (s *server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	s.metrics.render(w)
}

func (s *server) handleStatic(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Frame-Options", "DENY")

	clean := path.Clean("/" + r.URL.Path)
	if strings.HasPrefix(clean, "/api/") || clean == "/api" {
		http.NotFound(w, r)
		return
	}

	if clean == "/" {
		s.serveIndex(w, r)
		return
	}

	filePath := filepath.Join(s.cfg.staticDir, filepath.FromSlash(clean))
	info, err := os.Stat(filePath)
	if err == nil && !info.IsDir() {
		if strings.HasPrefix(clean, "/assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		} else {
			w.Header().Set("Cache-Control", "public, max-age=3600")
		}
		s.static.ServeHTTP(w, r)
		return
	}

	// A missing hashed asset is a real 404, not an SPA route.
	if strings.HasPrefix(clean, "/assets/") {
		http.NotFound(w, r)
		return
	}

	s.serveIndex(w, r)
}

func (s *server) serveIndex(w http.ResponseWriter, r *http.Request) {
	index := filepath.Join(s.cfg.staticDir, "index.html")
	info, err := os.Stat(index)
	if err != nil || info.IsDir() {
		s.log.Error("static index missing", "path", index, "error", err)
		http.Error(w, "frontend assets unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
	http.ServeFile(w, r, index)
}

func healthcheckURL() (string, error) {
	if raw := strings.TrimSpace(os.Getenv("HEALTHCHECK_URL")); raw != "" {
		return raw, nil
	}
	addr := envOr("LISTEN_ADDR", ":8080")
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return "", err
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return fmt.Sprintf("http://%s/healthz", net.JoinHostPort(host, port)), nil
}

func runHealthcheck() error {
	u, err := healthcheckURL()
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(u)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("healthcheck returned %d", resp.StatusCode)
	}
	return nil
}

func main() {
	check := flag.Bool("healthcheck", false, "probe the local /healthz endpoint and exit")
	flag.Parse()
	if *check {
		if err := runHealthcheck(); err != nil {
			fmt.Fprintln(os.Stderr, "healthcheck failed:", err)
			os.Exit(1)
		}
		return
	}

	cfg := loadConfig()
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.logLevel})
	log := slog.New(handler).With("service", "lowcode-web", "env", cfg.appEnv)
	srv := newServer(cfg, log)

	httpServer := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("server_start", "addr", cfg.listenAddr, "staticDir", cfg.staticDir, "version", envOr("APP_VERSION", version), "commit", envOr("GIT_COMMIT", commit))
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	select {
	case err := <-errCh:
		log.Error("server_error", "error", err)
		os.Exit(1)
	case sig := <-sigCh:
		log.Info("shutdown", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(ctx); err != nil {
			log.Error("shutdown_error", "error", err)
			os.Exit(1)
		}
	}
}
