package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"path/filepath"

	"github.com/Jesejojo3/asabiya-native/internal/interop"
)

func main() {
	port := flag.Int("port", 0, "loopback TCP port (0 selects an available port)")
	endpointFile := flag.String("endpoint-file", "", "also publish the assigned local endpoint to this JSON file")
	logFile := flag.String("log-file", "", "write startup/runtime errors to this local file")
	parentPID := flag.Int("parent-pid", 0, "Windows owner process; stop serving when it exits")
	flag.Parse()
	if *logFile != "" {
		f, err := os.OpenFile(*logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		os.Stderr = f
	}
	if *port < 0 || *port > 65535 {
		fmt.Fprintln(os.Stderr, "invalid port")
		os.Exit(1)
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	endpoint := map[string]any{"schema": "asabiya/local-endpoint-v1", "address": listener.Addr().String(), "protocol": interop.LocalSchema}
	if *endpointFile != "" {
		data, writeErr := json.Marshal(endpoint)
		if writeErr == nil {
			writeErr = os.MkdirAll(filepath.Dir(*endpointFile), 0755)
		}
		if writeErr == nil {
			writeErr = os.WriteFile(*endpointFile+".tmp", append(data, '\n'), 0644)
		}
		if writeErr == nil {
			writeErr = os.Rename(*endpointFile+".tmp", *endpointFile)
		}
		if writeErr != nil {
			fmt.Fprintln(os.Stderr, writeErr)
			listener.Close()
			os.Exit(1)
		}
		defer os.Remove(*endpointFile)
	}
	// A GUI-owned Windows child may have no stdout handle. The endpoint file
	// is sufficient in that mode; command-line callers still receive errors.
	if err = json.NewEncoder(os.Stdout).Encode(endpoint); err != nil && *endpointFile == "" {
		listener.Close()
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if *parentPID > 0 {
		go stopWhenParentExits(*parentPID, stop)
	}
	if err = interop.Serve(ctx, listener, &interop.Session{}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
