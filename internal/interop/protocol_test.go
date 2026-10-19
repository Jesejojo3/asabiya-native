package interop

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

type forbiddenListener struct{ accepted bool }

func (l *forbiddenListener) Addr() net.Addr { return &net.TCPAddr{IP: net.IPv4zero, Port: 1} }
func (l *forbiddenListener) Accept() (net.Conn, error) {
	l.accepted = true
	return nil, fmt.Errorf("must not accept")
}
func (l *forbiddenListener) Close() error { return nil }
func TestProtocolRefusesNonLoopbackWithoutAccepting(t *testing.T) {
	l := &forbiddenListener{}
	if err := Serve(context.Background(), l, &Session{}); err == nil || l.accepted {
		t.Fatal("non-loopback listener was allowed")
	}
}
func TestProtocolSessionBoundariesAndNoHiddenBatch(t *testing.T) {
	s := &Session{}
	request := func(op string, payload any) Response {
		data, _ := json.Marshal(payload)
		return s.Handle(Request{Schema: LocalSchema, ID: "test", Op: op, Payload: data})
	}
	if request("get_state", nil).OK {
		t.Fatal("uninitialized state returned")
	}
	config := sim.DefaultWorldConfig("protocol-session")
	config.Width, config.Height = 24, 16
	if !request("create_world", map[string]any{"world": config, "fine": false}).OK {
		t.Fatal("world failed")
	}
	created := s.generation
	if !request("start_history", map[string]any{"historySeed": "1"}).OK {
		t.Fatal("history failed")
	}
	if s.generation == created {
		t.Fatal("new history did not change session identity")
	}
	before := s.simulation.StateDigest()
	bad := s.Handle(Request{Schema: LocalSchema, ID: "stale", Session: created, Op: "advance"})
	if bad.OK || bad.Error.Code != "stale_session" {
		t.Fatal("stale client command accepted")
	}
	if request("advance", map[string]any{"years": 1000}).OK {
		t.Fatal("silently ignored unsupported batch")
	}
	if !request("pause", map[string]any{}).OK || s.simulation.StateDigest() != before {
		t.Fatal("pause/stale/invalid request changed historical state")
	}
	year := s.simulation.Status().Year
	if !request("advance", map[string]any{}).OK || s.simulation.Status().Year != year+1 {
		t.Fatal("advance is not one complete year")
	}
}
