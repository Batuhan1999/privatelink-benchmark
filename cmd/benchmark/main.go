package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"privatelink-benchmark/internal/sample"
)

type route struct {
	name string
	dsn  string
	cfg  *pgx.ConnConfig
	conn *pgx.Conn
}

type options struct {
	mode         string
	output       string
	runID        string
	iterations   int64
	duration     time.Duration
	interval     time.Duration
	timeout      time.Duration
	warmup       int
	payloadBytes int
	publicDSN    string
	privateDSN   string
}

func main() {
	opts := parseFlags()
	if err := run(opts); err != nil {
		fmt.Fprintln(os.Stderr, "benchmark:", err)
		os.Exit(1)
	}
}

func parseFlags() options {
	var opts options
	flag.StringVar(&opts.mode, "mode", "warm", "benchmark mode: tcp, cold, warm, or payload")
	flag.StringVar(&opts.output, "output", "results/samples.jsonl", "JSONL output file")
	flag.StringVar(&opts.runID, "run-id", "", "run identifier; generated when empty")
	flag.Int64Var(&opts.iterations, "iterations", 10000, "number of paired public/private iterations; use 0 with -duration")
	flag.DurationVar(&opts.duration, "duration", 0, "run duration; when set, takes precedence over -iterations")
	flag.DurationVar(&opts.interval, "interval", 100*time.Millisecond, "target interval between paired iterations")
	flag.DurationVar(&opts.timeout, "timeout", 5*time.Second, "timeout for each network or database operation")
	flag.IntVar(&opts.warmup, "warmup", 100, "unrecorded warm-up queries per path")
	flag.IntVar(&opts.payloadBytes, "payload-bytes", 1024, "response size for payload mode")
	flag.StringVar(&opts.publicDSN, "public-dsn", os.Getenv("PUBLIC_DATABASE_URL"), "public PlanetScale DSN; defaults to PUBLIC_DATABASE_URL")
	flag.StringVar(&opts.privateDSN, "private-dsn", os.Getenv("PRIVATE_DATABASE_URL"), "PrivateLink PlanetScale DSN; defaults to PRIVATE_DATABASE_URL")
	flag.Parse()
	return opts
}

func run(opts options) error {
	if opts.publicDSN == "" || opts.privateDSN == "" {
		return errors.New("PUBLIC_DATABASE_URL and PRIVATE_DATABASE_URL are required")
	}
	if opts.runID == "" {
		opts.runID = time.Now().UTC().Format("20060102T150405.000000000Z")
	}
	if opts.duration <= 0 && opts.iterations <= 0 {
		return errors.New("set a positive -iterations or -duration")
	}
	if opts.payloadBytes < 0 || opts.payloadBytes > 16*1024*1024 {
		return errors.New("payload-bytes must be between 0 and 16777216")
	}
	if !validMode(opts.mode) {
		return fmt.Errorf("unsupported mode %q", opts.mode)
	}

	routes, err := makeRoutes(opts)
	if err != nil {
		return err
	}
	defer closeRoutes(routes)

	if opts.mode == "warm" || opts.mode == "payload" {
		if err := connectAndWarm(routes, opts); err != nil {
			return err
		}
	}

	if err := os.MkdirAll(filepath.Dir(opts.output), 0o755); err != nil {
		return err
	}
	f, err := os.Create(opts.output)
	if err != nil {
		return err
	}
	defer f.Close()
	w := bufio.NewWriterSize(f, 256*1024)
	defer w.Flush()
	enc := json.NewEncoder(w)

	seed := time.Now().UnixNano()
	rng := rand.New(rand.NewSource(seed))
	started := time.Now()
	deadline := started.Add(opts.duration)
	next := started
	var completed int64
	var failures int64

	for i := int64(0); ; i++ {
		if opts.duration > 0 {
			if i > 0 && time.Now().After(deadline) {
				break
			}
		} else if i >= opts.iterations {
			break
		}

		order := [2]int{0, 1}
		if rng.Intn(2) == 1 {
			order = [2]int{1, 0}
		}
		for sequence, index := range order {
			samples := measure(routes[index], opts, i, sequence)
			for _, result := range samples {
				if !result.OK {
					failures++
				}
				if err := enc.Encode(result); err != nil {
					return err
				}
			}
		}

		completed++
		if completed%1000 == 0 {
			if err := w.Flush(); err != nil {
				return err
			}
			fmt.Fprintf(os.Stderr, "completed=%d failures=%d elapsed=%s\n", completed, failures, time.Since(started).Round(time.Second))
		}
		if opts.interval > 0 {
			next = next.Add(opts.interval)
			if sleep := time.Until(next); sleep > 0 {
				time.Sleep(sleep)
			}
		}
	}

	fmt.Printf("run_id=%s mode=%s paired_iterations=%d failures=%d output=%s\n", opts.runID, opts.mode, completed, failures, opts.output)
	return nil
}

func validMode(mode string) bool {
	switch mode {
	case "tcp", "cold", "warm", "payload":
		return true
	default:
		return false
	}
}

func makeRoutes(opts options) ([]*route, error) {
	routes := []*route{{name: "public", dsn: opts.publicDSN}, {name: "private", dsn: opts.privateDSN}}
	for _, r := range routes {
		cfg, err := pgx.ParseConfig(r.dsn)
		if err != nil {
			return nil, fmt.Errorf("parse %s DSN: %w", r.name, err)
		}
		cfg.ConnectTimeout = opts.timeout
		r.cfg = cfg
	}
	return routes, nil
}

func connectAndWarm(routes []*route, opts options) error {
	for _, r := range routes {
		ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
		conn, err := pgx.ConnectConfig(ctx, r.cfg.Copy())
		cancel()
		if err != nil {
			return fmt.Errorf("connect %s route: %w", r.name, cleanError(err, routes))
		}
		r.conn = conn
		for i := 0; i < opts.warmup; i++ {
			ctx, cancel = context.WithTimeout(context.Background(), opts.timeout)
			var value int
			err = conn.QueryRow(ctx, "SELECT 1").Scan(&value)
			cancel()
			if err != nil {
				return fmt.Errorf("warm %s route: %w", r.name, cleanError(err, routes))
			}
		}
	}
	return nil
}

func closeRoutes(routes []*route) {
	for _, r := range routes {
		if r.conn != nil {
			_ = r.conn.Close(context.Background())
		}
	}
}

func measure(r *route, opts options, iteration int64, sequence int) []sample.Sample {
	switch opts.mode {
	case "tcp":
		return []sample.Sample{measureTCP(r, opts, iteration, sequence)}
	case "cold":
		return measureCold(r, opts, iteration, sequence)
	case "warm":
		return []sample.Sample{measureWarm(r, opts, iteration, sequence)}
	case "payload":
		return []sample.Sample{measurePayload(r, opts, iteration, sequence)}
	default:
		panic("validated mode became invalid")
	}
}

func baseSample(r *route, opts options, iteration int64, sequence int, mode string) sample.Sample {
	return sample.Sample{
		SchemaVersion: sample.SchemaVersion,
		RunID:         opts.runID,
		Timestamp:     time.Now().UTC(),
		Iteration:     iteration,
		Sequence:      sequence,
		Path:          r.name,
		Mode:          mode,
	}
}

func measureTCP(r *route, opts options, iteration int64, sequence int) sample.Sample {
	result := baseSample(r, opts, iteration, sequence, "tcp")
	address := net.JoinHostPort(r.cfg.Host, strconv.Itoa(int(r.cfg.Port)))
	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()
	start := time.Now()
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp", address)
	result.DurationNS = time.Since(start).Nanoseconds()
	if err == nil {
		result.OK = true
		_ = conn.Close()
	} else {
		result.Error = cleanError(err, []*route{r}).Error()
	}
	return result
}

func measureCold(r *route, opts options, iteration int64, sequence int) []sample.Sample {
	connectResult := baseSample(r, opts, iteration, sequence, "cold_connect")
	totalResult := baseSample(r, opts, iteration, sequence, "cold_total")
	totalStart := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	connectStart := time.Now()
	conn, err := pgx.ConnectConfig(ctx, r.cfg.Copy())
	connectResult.DurationNS = time.Since(connectStart).Nanoseconds()
	cancel()
	if err != nil {
		message := cleanError(err, []*route{r}).Error()
		connectResult.Error = message
		totalResult.DurationNS = time.Since(totalStart).Nanoseconds()
		totalResult.Error = message
		return []sample.Sample{connectResult, totalResult}
	}
	connectResult.OK = true
	defer conn.Close(context.Background())

	ctx, cancel = context.WithTimeout(context.Background(), opts.timeout)
	var value int
	err = conn.QueryRow(ctx, "SELECT 1").Scan(&value)
	cancel()
	totalResult.DurationNS = time.Since(totalStart).Nanoseconds()
	if err == nil && value == 1 {
		totalResult.OK = true
	} else if err != nil {
		totalResult.Error = cleanError(err, []*route{r}).Error()
	} else {
		totalResult.Error = "unexpected SELECT 1 result"
	}
	return []sample.Sample{connectResult, totalResult}
}

func measureWarm(r *route, opts options, iteration int64, sequence int) sample.Sample {
	result := baseSample(r, opts, iteration, sequence, "warm_select_1")
	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()
	start := time.Now()
	var value int
	err := r.conn.QueryRow(ctx, "SELECT 1").Scan(&value)
	result.DurationNS = time.Since(start).Nanoseconds()
	if err == nil && value == 1 {
		result.OK = true
	} else if err != nil {
		result.Error = cleanError(err, []*route{r}).Error()
	} else {
		result.Error = "unexpected SELECT 1 result"
	}
	return result
}

func measurePayload(r *route, opts options, iteration int64, sequence int) sample.Sample {
	result := baseSample(r, opts, iteration, sequence, "payload")
	result.PayloadBytes = opts.payloadBytes
	ctx, cancel := context.WithTimeout(context.Background(), opts.timeout)
	defer cancel()
	start := time.Now()
	var value string
	err := r.conn.QueryRow(ctx, "SELECT repeat('x', $1)::text", opts.payloadBytes).Scan(&value)
	result.DurationNS = time.Since(start).Nanoseconds()
	if err == nil && len(value) == opts.payloadBytes {
		result.OK = true
	} else if err != nil {
		result.Error = cleanError(err, []*route{r}).Error()
	} else {
		result.Error = fmt.Sprintf("payload length mismatch: got %d", len(value))
	}
	return result
}

func cleanError(err error, routes []*route) error {
	if err == nil {
		return nil
	}
	message := err.Error()
	for _, r := range routes {
		if r.dsn != "" {
			message = strings.ReplaceAll(message, r.dsn, "[redacted-dsn]")
		}
	}
	message = strings.ReplaceAll(message, "\n", " ")
	if len(message) > 500 {
		message = message[:500]
	}
	return errors.New(message)
}
