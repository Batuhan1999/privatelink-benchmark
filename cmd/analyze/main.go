package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"privatelink-benchmark/internal/sample"
)

type stringList []string

func (s *stringList) String() string { return strings.Join(*s, ",") }
func (s *stringList) Set(value string) error {
	*s = append(*s, value)
	return nil
}

type groupKey struct {
	mode string
	path string
}

type group struct {
	durations []time.Duration
	total     int
	errors    int
}

type pairKey struct {
	runID     string
	mode      string
	iteration int64
}

type pair struct {
	public  *time.Duration
	private *time.Duration
}

func main() {
	var inputs stringList
	var output string
	flag.Var(&inputs, "input", "input JSONL file; repeat for multiple files")
	flag.StringVar(&output, "output", "results/summary.md", "Markdown summary path")
	flag.Parse()
	if len(inputs) == 0 {
		fmt.Fprintln(os.Stderr, "analyze: at least one -input is required")
		os.Exit(2)
	}
	if err := run(inputs, output); err != nil {
		fmt.Fprintln(os.Stderr, "analyze:", err)
		os.Exit(1)
	}
}

func run(inputs []string, output string) error {
	groups := map[groupKey]*group{}
	pairs := map[pairKey]*pair{}
	for _, input := range inputs {
		if err := readFile(input, groups, pairs); err != nil {
			return err
		}
	}

	var report strings.Builder
	report.WriteString("# PrivateLink benchmark summary\n\n")
	report.WriteString("Lower latency is better. Paired deltas are `private - public`; negative values favor PrivateLink.\n\n")
	report.WriteString("| Mode | Path | Samples | Errors | p50 | p95 | p99 | p99.9 |\n")
	report.WriteString("|---|---:|---:|---:|---:|---:|---:|---:|\n")
	keys := make([]groupKey, 0, len(groups))
	for key := range groups {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].mode == keys[j].mode {
			return keys[i].path < keys[j].path
		}
		return keys[i].mode < keys[j].mode
	})
	for _, key := range keys {
		g := groups[key]
		sort.Slice(g.durations, func(i, j int) bool { return g.durations[i] < g.durations[j] })
		fmt.Fprintf(&report, "| %s | %s | %d | %d | %s | %s | %s | %s |\n",
			key.mode, key.path, g.total, g.errors,
			formatDuration(quantile(g.durations, 0.50)),
			formatDuration(quantile(g.durations, 0.95)),
			formatDuration(quantile(g.durations, 0.99)),
			formatDuration(quantile(g.durations, 0.999)))
	}

	deltasByMode := map[string][]time.Duration{}
	for key, pair := range pairs {
		if pair.public == nil || pair.private == nil {
			continue
		}
		deltasByMode[key.mode] = append(deltasByMode[key.mode], *pair.private-*pair.public)
	}
	if len(deltasByMode) > 0 {
		report.WriteString("\n## Paired latency delta\n\n")
		report.WriteString("| Mode | Complete pairs | p50 delta | p95 delta | p99 delta |\n")
		report.WriteString("|---|---:|---:|---:|---:|\n")
		modes := make([]string, 0, len(deltasByMode))
		for mode := range deltasByMode {
			modes = append(modes, mode)
		}
		sort.Strings(modes)
		for _, mode := range modes {
			deltas := deltasByMode[mode]
			sort.Slice(deltas, func(i, j int) bool { return deltas[i] < deltas[j] })
			fmt.Fprintf(&report, "| %s | %d | %s | %s | %s |\n", mode, len(deltas),
				formatSignedDuration(quantile(deltas, 0.50)),
				formatSignedDuration(quantile(deltas, 0.95)),
				formatSignedDuration(quantile(deltas, 0.99)))
		}
	}

	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(output, []byte(report.String()), 0o644); err != nil {
		return err
	}
	fmt.Print(report.String())
	return nil
}

func readFile(path string, groups map[groupKey]*group, pairs map[pairKey]*pair) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		var s sample.Sample
		if err := json.Unmarshal(scanner.Bytes(), &s); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		key := groupKey{mode: s.Mode, path: s.Path}
		g := groups[key]
		if g == nil {
			g = &group{}
			groups[key] = g
		}
		g.total++
		if !s.OK {
			g.errors++
			continue
		}
		duration := s.Duration()
		g.durations = append(g.durations, duration)
		pk := pairKey{runID: s.RunID, mode: s.Mode, iteration: s.Iteration}
		p := pairs[pk]
		if p == nil {
			p = &pair{}
			pairs[pk] = p
		}
		value := duration
		if s.Path == "public" {
			p.public = &value
		} else if s.Path == "private" {
			p.private = &value
		}
	}
	return scanner.Err()
}

func quantile(values []time.Duration, q float64) time.Duration {
	if len(values) == 0 {
		return 0
	}
	index := int(q * float64(len(values)-1))
	if index < 0 {
		index = 0
	}
	if index >= len(values) {
		index = len(values) - 1
	}
	return values[index]
}

func formatDuration(value time.Duration) string {
	if value == 0 {
		return "—"
	}
	return fmt.Sprintf("%.3f ms", float64(value)/float64(time.Millisecond))
}

func formatSignedDuration(value time.Duration) string {
	return fmt.Sprintf("%+.3f ms", float64(value)/float64(time.Millisecond))
}
