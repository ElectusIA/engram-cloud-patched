package cloudserver

import (
	"os"
	"regexp"
)

// Build identity is fixed in the patched source; only the inspected image digest
// is supplied by the deployment. Never echo arbitrary environment metadata.
func electusHealthMetadata() map[string]any {
	result := map[string]any{"status": "ok", "service": "engram-cloud", "version": "3.0.0", "patchRevision": "electus-3.0.0-patch3"}
	if value := os.Getenv("ENGRAM_IMAGE_DIGEST"); regexp.MustCompile(`^sha256:[a-f0-9]{64}$`).MatchString(value) {
		result["imageDigest"] = value
	}
	return result
}
