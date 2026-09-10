package cloudstore

import "testing"

func TestElectusIssuedTokenAuditMetadata(t *testing.T) {
	if err := rejectSensitiveAuthAuditMetadata(map[string]any{"issued_token": true}); err != nil {
		t.Fatalf("boolean issued_token must remain permitted for managed token bootstrap: %v", err)
	}
	for _, key := range []string{"raw_token", "token_hash", "authorization", "password", "issued_token_secret"} {
		if !sensitiveAuthAuditKey(key) {
			t.Fatalf("sensitive metadata %q must still be rejected", key)
		}
	}
}
