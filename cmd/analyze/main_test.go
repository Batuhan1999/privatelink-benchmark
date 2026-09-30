package main

import (
	"testing"
	"time"
)

func TestQuantileIndex(t *testing.T) {
	values := []time.Duration{
		1 * time.Millisecond,
		2 * time.Millisecond,
		3 * time.Millisecond,
		4 * time.Millisecond,
		5 * time.Millisecond,
	}
	tests := []struct {
		q    float64
		want time.Duration
	}{
		{q: 0, want: time.Millisecond},
		{q: 0.5, want: 3 * time.Millisecond},
		{q: 0.95, want: 4 * time.Millisecond},
		{q: 1, want: 5 * time.Millisecond},
	}
	for _, test := range tests {
		if got := quantile(values, test.q); got != test.want {
			t.Fatalf("quantile(%v): got %v, want %v", test.q, got, test.want)
		}
	}
}

func TestQuantileEmpty(t *testing.T) {
	if got := quantile(nil, 0.5); got != 0 {
		t.Fatalf("got %v, want zero", got)
	}
}

func TestDurationFormatting(t *testing.T) {
	if got := formatDuration(1500 * time.Microsecond); got != "1.500 ms" {
		t.Fatalf("got %q", got)
	}
	if got := formatSignedDuration(-250 * time.Microsecond); got != "-0.250 ms" {
		t.Fatalf("got %q", got)
	}
}
