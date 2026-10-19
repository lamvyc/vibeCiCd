package main

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func testServer(t *testing.T, staticDir string, failReady bool) *server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	return newServer(config{
		listenAddr: ":0",
		staticDir:  staticDir,
		appEnv:     "test",
		failReady:  failReady,
		logLevel:   slog.LevelError,
	}, log)
}

func writeStatic(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<!doctype html><title>lowcode</title>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "app-abc123.js"), []byte("console.log('ok')"), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func do(t *testing.T, h http.Handler, method, target string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, target, nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHealthz(t *testing.T) {
	s := testServer(t, writeStatic(t), false)
	rec := do(t, s.Handler(), http.MethodGet, "/healthz")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"status":"ok"`) {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestReadyz(t *testing.T) {
	ok := testServer(t, writeStatic(t), false)
	if rec := do(t, ok.Handler(), http.MethodGet, "/readyz"); rec.Code != http.StatusOK {
		t.Fatalf("ready status = %d, want 200", rec.Code)
	}

	bad := testServer(t, writeStatic(t), true)
	rec := do(t, bad.Handler(), http.MethodGet, "/readyz")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("not-ready status = %d, want 503", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "FAIL_READY") {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestVersion(t *testing.T) {
	t.Setenv("APP_VERSION", "v1.2.3")
	t.Setenv("GIT_COMMIT", "abc123")
	t.Setenv("BUILD_TIME", "2026-10-19T00:00:00Z")
	s := testServer(t, writeStatic(t), false)
	rec := do(t, s.Handler(), http.MethodGet, "/api/version")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{"v1.2.3", "abc123", "2026-10-19T00:00:00Z", `"env":"test"`, "goVersion"} {
		if !strings.Contains(body, want) {
			t.Fatalf("body missing %q: %s", want, body)
		}
	}
}

func TestStaticAndSPAFallback(t *testing.T) {
	s := testServer(t, writeStatic(t), false)
	h := s.Handler()

	root := do(t, h, http.MethodGet, "/")
	if root.Code != http.StatusOK || !strings.Contains(root.Body.String(), "<!doctype html>") {
		t.Fatalf("root = %d %q", root.Code, root.Body.String())
	}

	asset := do(t, h, http.MethodGet, "/assets/app-abc123.js")
	if asset.Code != http.StatusOK || !strings.Contains(asset.Body.String(), "console.log") {
		t.Fatalf("asset = %d %q", asset.Code, asset.Body.String())
	}
	if got := asset.Header().Get("Cache-Control"); !strings.Contains(got, "immutable") {
		t.Fatalf("asset cache-control = %q", got)
	}

	route := do(t, h, http.MethodGet, "/editor/page/1")
	if route.Code != http.StatusOK || !strings.Contains(route.Body.String(), "<!doctype html>") {
		t.Fatalf("spa fallback = %d %q", route.Code, route.Body.String())
	}
	if got := route.Header().Get("Cache-Control"); got != "no-cache" {
		t.Fatalf("index cache-control = %q", got)
	}
}

func TestMissingAssetAndAPI(t *testing.T) {
	s := testServer(t, writeStatic(t), false)
	h := s.Handler()

	if rec := do(t, h, http.MethodGet, "/assets/missing.js"); rec.Code != http.StatusNotFound {
		t.Fatalf("missing asset = %d, want 404", rec.Code)
	}
	if rec := do(t, h, http.MethodGet, "/api/missing"); rec.Code != http.StatusNotFound {
		t.Fatalf("missing api = %d, want 404", rec.Code)
	}
	if rec := do(t, h, http.MethodPost, "/healthz"); rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("post healthz = %d, want 405", rec.Code)
	}
}

func TestMetrics(t *testing.T) {
	s := testServer(t, writeStatic(t), false)
	h := s.Handler()
	do(t, h, http.MethodGet, "/healthz")
	do(t, h, http.MethodGet, "/api/version")

	rec := do(t, h, http.MethodGet, "/metrics")
	if rec.Code != http.StatusOK {
		t.Fatalf("metrics status = %d", rec.Code)
	}
	body := rec.Body.String()
	for _, want := range []string{
		"lowcode_build_info",
		`lowcode_http_requests_total{method="GET",route="/healthz",status="200"} 1`,
		"lowcode_http_request_duration_seconds_bucket",
		"lowcode_http_request_duration_seconds_count",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("metrics missing %q\n%s", want, body)
		}
	}
}

func TestMissingIndex(t *testing.T) {
	dir := t.TempDir()
	s := testServer(t, dir, false)
	if rec := do(t, s.Handler(), http.MethodGet, "/"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}

func TestNormalizeRoute(t *testing.T) {
	cases := map[string]string{
		"/":              "/",
		"/healthz":       "/healthz",
		"/api/version":   "/api/version",
		"/api/anything":  "/api/*",
		"/assets/app.js": "/assets/*",
		"/assets/deep/x": "/assets/*",
		"/editor/page/1": "other",
		"/metrics":       "/metrics",
	}
	for in, want := range cases {
		if got := normalizeRoute(in); got != want {
			t.Errorf("normalizeRoute(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHealthcheckURL(t *testing.T) {
	t.Setenv("LISTEN_ADDR", ":8080")
	t.Setenv("HEALTHCHECK_URL", "")
	got, err := healthcheckURL()
	if err != nil {
		t.Fatal(err)
	}
	if got != "http://127.0.0.1:8080/healthz" {
		t.Fatalf("url = %q", got)
	}
}
