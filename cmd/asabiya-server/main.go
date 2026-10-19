package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"

	"github.com/Jesejojo3/asabiya-native/internal/interop"
)

func main() {
	port := flag.Int("port", 0, "loopback TCP port (0 selects an available port)")
	flag.Parse()
	if *port < 0 || *port > 65535 {
		fmt.Fprintln(os.Stderr, "invalid port")
		os.Exit(1)
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err = json.NewEncoder(os.Stdout).Encode(map[string]any{"schema": "asabiya/local-endpoint-v1", "address": listener.Addr().String(), "protocol": interop.LocalSchema}); err != nil {
		listener.Close()
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if err = interop.Serve(ctx, listener, &interop.Session{}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
