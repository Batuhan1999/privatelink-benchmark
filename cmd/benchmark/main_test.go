package main

import (
	"errors"
	"strings"
	"testing"
)

func TestValidMode(t *testing.T) {
	for _, mode := range []string{"tcp", "cold", "warm", "payload"} {
		if !validMode(mode) {
			t.Fatalf("expected %q to be valid", mode)
		}
	}
	if validMode("unknown") {
		t.Fatal("unexpected valid mode")
	}
}

func TestCleanErrorRedactsDSN(t *testing.T) {
	dsn := "postgresql://user:secret@example.test/postgres"
	err := cleanError(errors.New("connect "+dsn+"\nfailed"), []*route{{dsn: dsn}})
	if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), dsn) {
		t.Fatalf("DSN leaked in error: %q", err)
	}
	if strings.Contains(err.Error(), "\n") {
		t.Fatalf("newline was not removed: %q", err)
	}
	if !strings.Contains(err.Error(), "[redacted-dsn]") {
		t.Fatalf("redaction marker missing: %q", err)
	}
}
