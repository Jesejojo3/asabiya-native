package interop

import (
	"encoding/json"
	"testing"

	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

func TestGodotCommandContextAndReplay(t *testing.T) {
	s := &Session{}
	call := func(op string, payload any) Response {
		raw, err := json.Marshal(payload)
		if err != nil {
			t.Fatal(err)
		}
		return s.Handle(Request{Schema: LocalSchema, ID: op, Op: op, Payload: raw})
	}
	cfg := sim.DefaultWorldConfig("godot-command-ui")
	cfg.Width, cfg.Height = 24, 16
	if r := call("create_world", map[string]any{"world": cfg, "fine": false}); !r.OK {
		t.Fatalf("create_world: %+v", r.Error)
	}
	if r := call("start_history", map[string]any{"historySeed": "command-replay", "view": "map-columns-v1"}); !r.OK {
		t.Fatalf("start_history: %+v", r.Error)
	}
	catalog := call("get_catalog", map[string]any{})
	if !catalog.OK {
		t.Fatalf("catalog error: %+v", catalog.Error)
	}
	cat, ok := catalog.Data.(map[string]any)
	if !ok || len(cat["omens"].([]sim.OmenDef)) != 8 || len(cat["parameters"].([]sim.ParameterDef)) == 0 {
		t.Fatal("Godot did not receive the canonical intervention and rules catalog")
	}

	getContext := func() sim.CommandContext {
		response := call("get_status", map[string]any{})
		if !response.OK {
			t.Fatalf("get_status: %+v", response.Error)
		}
		return response.Data.(map[string]any)["commandContext"].(sim.CommandContext)
	}
	initial := getContext()
	if initial.NextSequence != 1 || initial.RulesSHA256 == "" {
		t.Fatalf("invalid initial context: %+v", initial)
	}
	valid := sim.Command{
		Schema: sim.CommandSchema, Profile: sim.NativeProfile,
		Kind: "set_sandbox", TargetYear: initial.Year,
		Sequence: initial.NextSequence, ExpectedRulesSHA256: initial.RulesSHA256,
		Sandbox: func() *bool { enabled := true; return &enabled }(),
	}
	before := s.simulation.StateDigest()
	reply := call("apply_command_status", valid)
	if !reply.OK {
		t.Fatalf("compact command response error: %+v", reply.Error)
	}
	data := reply.Data.(map[string]any)
	if _, leaksState := data["state"]; leaksState {
		t.Fatal("compact command response unexpectedly included full province state")
	}
	if !data["result"].(sim.CommandResult).Accepted {
		t.Fatalf("sandbox rejected: %+v", data["result"])
	}
	updated := data["commandContext"].(sim.CommandContext)
	if !updated.Rules.Sandbox || updated.Favor != 9 || updated.NextSequence != initial.NextSequence+1 || s.simulation.StateDigest() == before {
		t.Fatal("sandbox result was not committed and exposed coherently")
	}
	stale := valid
	stale.Kind = "change_rules"
	stale.Sandbox = nil
	stale.Values = map[string]float64{}
	rejected := call("apply_command_status", stale)
	if !rejected.OK || rejected.Data.(map[string]any)["result"].(sim.CommandResult).Accepted {
		t.Fatal("stale sequence command was accepted")
	}
	if s.simulation.NextSequence() != updated.NextSequence {
		t.Fatal("rejected command consumed an accepted sequence")
	}
	replay := s.simulation.Replay()
	reproduced, err := sim.ReplayOnWorld(s.world, replay)
	if err != nil || reproduced.StateDigest() != s.simulation.StateDigest() {
		t.Fatalf("replay diverged after accepted and rejected UI commands: %v", err)
	}
}
