package sample

import "time"

const SchemaVersion = 1

type Sample struct {
	SchemaVersion int       `json:"schema_version"`
	RunID         string    `json:"run_id"`
	Timestamp     time.Time `json:"timestamp"`
	Iteration     int64     `json:"iteration"`
	Sequence      int       `json:"sequence"`
	Path          string    `json:"path"`
	Mode          string    `json:"mode"`
	DurationNS    int64     `json:"duration_ns"`
	OK            bool      `json:"ok"`
	Error         string    `json:"error,omitempty"`
	PayloadBytes  int       `json:"payload_bytes,omitempty"`
}

func (s Sample) Duration() time.Duration {
	return time.Duration(s.DurationNS)
}
