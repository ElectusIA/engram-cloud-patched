package cloudserver

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestElectusHealthBuildIdentity(t *testing.T) {
	for _, digest := range []string{"", "not-a-digest", "sha256:" + strings.Repeat("a", 64)} {
		t.Run(digest, func(t *testing.T) {
			t.Setenv("ENGRAM_IMAGE_DIGEST", digest)
			response := httptest.NewRecorder()
			(&CloudServer{}).handleHealth(response, httptest.NewRequest("GET", "/health", nil))
			var body map[string]any
			if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil { t.Fatal(err) }
			if response.Code != 200 || body["version"] != "1.20.0" || body["patchRevision"] != "electus-1.20.0-patch2" { t.Fatalf("missing build identity: %v", body) }
			if strings.HasPrefix(digest, "sha256:") { if body["imageDigest"] != digest { t.Fatal("valid deployment digest missing") } } else if _, exists := body["imageDigest"]; exists { t.Fatal("unverified digest exposed") }
		})
	}
}
