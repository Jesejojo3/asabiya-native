package interop

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"path/filepath"
	"sync"
 "time"
 "io"
 "github.com/Jesejojo3/asabiya-native/internal/telemetry"

	"github.com/Jesejojo3/asabiya-native/internal/mapsource"
	"github.com/Jesejojo3/asabiya-native/internal/sim"
)

const LocalSchema = "asabiya/local-v1"

type Request struct {
	Schema  string          `json:"schema"`
	ID      string          `json:"id"`
	Session uint64          `json:"session,omitempty"`
	Op      string          `json:"op"`
	Payload json.RawMessage `json:"payload,omitempty"`
}
type ProtocolError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
type Response struct {
	Year    *int           `json:"year,omitempty"`
	Schema  string         `json:"schema"`
	ID      string         `json:"id"`
	Session uint64         `json:"session"`
	OK      bool           `json:"ok"`
	Data    any            `json:"data,omitempty"`
	Error   *ProtocolError `json:"error,omitempty"`
}
type Session struct {
 trace *telemetry.Trace
	mu           sync.Mutex
	generation   uint64
	world        *sim.World
	surface      *sim.Surface
	simulation   *sim.Simulation
	mapCache     []mapProvince
	mapCacheYear int
	entityCache map[string]map[int]sim.EntityRecord
	entityCacheYear int
}

func decodePayload(raw json.RawMessage, target any) error {
	if len(raw) == 0 {
		raw = []byte("{}")
	}
	// A payload is one JSON value, including when Handle is called directly.
	if !json.Valid(raw) {
		return fmt.Errorf("payload must contain one valid JSON value")
	}
	decoder := json.NewDecoder(bytes.NewReader(normalizeJSONIntegers(raw)))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}
func (s *Session) Handle(req Request) Response {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.trace != nil {
		start:=time.Now()
		defer func(){ fields:=map[string]any{"op":req.Op}
			if s.simulation!=nil { fields["year"]=s.simulation.Status().Year;fields["profile"]=s.simulation.WorkProfile() }
			s.trace.Record("handle",time.Since(start),fields)
		}()
	}
	response := Response{Schema: LocalSchema, ID: req.ID, Session: s.generation}
	fail := func(code string, err error) Response {
		response.Error = &ProtocolError{Code: code, Message: err.Error()}
		return response
	}
	if req.Schema != LocalSchema || req.ID == "" {
		return fail("invalid_request", fmt.Errorf("schema %s and nonempty id are required", LocalSchema))
	}
	if req.Session != 0 && req.Session != s.generation {
		return fail("stale_session", fmt.Errorf("session has changed"))
	}
	switch req.Op {
	case "create_world":
		s.mapCache = nil
		s.entityCache = nil
		var payload struct {
			World  *sim.WorldConfig `json:"world"`
			Fine   *bool            `json:"fine"`
			Source *sim.WorldSource `json:"source"`
		}
		defaultSource := sim.DefaultWorldSource()
		payload.Source = &defaultSource
		if err := decodePayload(req.Payload, &payload); err != nil {
			return fail("invalid_arguments", err)
		}
		config := sim.DefaultWorldConfig("Asabiya")
		if payload.World != nil {
			config = *payload.World
		}
		var w *sim.World
		var surface *sim.Surface
		var err error
		source := sim.DefaultWorldSource()
		if payload.Source != nil {
			source = *payload.Source
		}
		w, surface, err = mapsource.Generate(config, source, payload.Fine == nil || *payload.Fine)
		if err != nil {
			return fail("invalid_arguments", err)
		}
		s.world = w
		s.surface = surface
		s.simulation = nil
		s.generation++
		response.Session = s.generation
		response.Data = w.Summary()
	case "start_history":
		s.mapCache = nil
		s.entityCache = nil
		if s.world == nil {
			return fail("not_ready", fmt.Errorf("create_world first"))
		}
		var payload struct {
			HistorySeed string     `json:"historySeed"`
			Rules       *sim.Rules `json:"rules"`
			View        string     `json:"view"`
		}
		if err := decodePayload(req.Payload, &payload); err != nil {
			return fail("invalid_arguments", err)
		}
		if payload.View != "" && payload.View != "map" && payload.View != "map-columns-v1" {
			return fail("invalid_arguments", fmt.Errorf("unknown state view"))
		}
		rules := sim.DefaultRules()
		if payload.Rules != nil {
			rules = *payload.Rules
		}
		history, err := sim.NewSimulationWithRules(s.world, payload.HistorySeed, rules)
		if err != nil {
			return fail("invalid_arguments", err)
		}
		s.simulation = history
        if s.trace != nil { s.simulation.EnableWorkProfile() }
		s.generation++
		response.Session = s.generation
		if payload.View == "map" || payload.View == "map-columns-v1" {
			view:=s.cacheMapState(s.simulation.MapSnapshot());if payload.View=="map-columns-v1" {response.Data=packState(view)}else{response.Data=view}
		} else {
			response.Data = s.simulation.Snapshot()
		}
	case "get_world":
		if s.world == nil {
			return fail("not_ready", fmt.Errorf("create_world first"))
		}
		response.Data = s.world.Summary()
	case "get_catalog":
		response.Data = map[string]any{"schema": "asabiya/catalog-v1", "technologies": sim.TechCatalog(), "eras": sim.Eras(), "mapColumnsV1": true, "entityChangesV1": true}
	case "export_geography":
		if s.world == nil {
			return fail("not_ready", fmt.Errorf("create_world first"))
		}
		var payload struct {
			Directory string `json:"directory"`
		}
		if err := decodePayload(req.Payload, &payload); err != nil {
			return fail("invalid_arguments", err)
		}
		if payload.Directory == "" {
			return fail("invalid_arguments", fmt.Errorf("directory is required"))
		}
		directory, err := filepath.Abs(payload.Directory)
		if err != nil {
			return fail("invalid_arguments", err)
		}
		if _, err = WriteGeography(directory, s.world, s.surface); err != nil {
			return fail("export_failed", err)
		}
		response.Data = map[string]any{"directory": directory, "manifest": "manifest.json"}
	case "pause":
		if err := decodePayload(req.Payload, &struct{}{}); err != nil {
			return fail("invalid_arguments", err)
		}
		response.Data = map[string]any{"paused": true, "mode": "request-driven"}
	case "shutdown":
		response.Data = map[string]any{"shutdown": true}
	default:
		if s.simulation == nil {
			return fail("not_ready", fmt.Errorf("start_history first"))
		}
		switch req.Op {
		case "get_state":
			var payload struct {
				View string `json:"view"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			if payload.View != "" && payload.View != "map" && payload.View != "map-columns-v1" {
				return fail("invalid_arguments", fmt.Errorf("unknown state view"))
			}
			if payload.View == "map" || payload.View == "map-columns-v1" {
				view:=s.cacheMapState(s.simulation.MapSnapshot());if payload.View=="map-columns-v1" {response.Data=packState(view)}else{response.Data=view}
			} else {
				response.Data = s.simulation.Snapshot()
			}
		case "get_status":
			response.Data = map[string]any{"status": s.simulation.Status(), "nextSequence": s.simulation.NextSequence(), "rulesSHA256": s.simulation.RulesDigest()}
		case "advance":
			var payload struct {
				View        string `json:"view"`
				Publication string `json:"publication"`
				EntityMode string `json:"entityMode"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			if (payload.View != "" && payload.View != "map" && payload.View != "map-columns-v1") || (payload.Publication != "" && payload.Publication != "status") || (payload.EntityMode != "" && (payload.EntityMode != "changed" || payload.View != "map-columns-v1" || payload.Publication != "")) {
				return fail("invalid_arguments", fmt.Errorf("unknown publication/view"))
			}
			if payload.Publication == "status" {
				s.mapCache = nil
		s.entityCache = nil
				s.simulation.AdvanceYear()
				status := s.simulation.Status()
				response.Data = map[string]any{"schema": "asabiya/advance-status-v1", "year": status.Year, "rng": status.HistoryRNG}
			} else {
				if payload.View == "map" || payload.View == "map-columns-v1" {
					view := s.filterMapDelta(s.simulation.AdvanceYearWithMapDelta())
					if payload.EntityMode == "changed" {
						s.filterEntityChanges(&view)
					} else {
						// Switching between complete and sparse publications must
						// always restart the entity baseline from a full snapshot.
						s.entityCache = nil
					}
					if payload.View == "map-columns-v1" {
						response.Data = packDelta(view)
					} else {
						response.Data = view
					}
				} else {
					s.mapCache = nil
		s.entityCache = nil
					response.Data = s.simulation.AdvanceYearWithDelta()
				}
			}
		case "apply_command":
			s.mapCache = nil
		s.entityCache = nil
			var command sim.Command
			if err := decodePayload(req.Payload, &command); err != nil {
				return fail("invalid_arguments", err)
			}
			result := s.simulation.ApplyCommand(command)
			response.Data = map[string]any{"result": result, "state": s.simulation.Snapshot()}
		case "get_province", "get_province_history":
			var payload struct {
				ID sim.CellID `json:"id"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			province, ok := s.simulation.Province(payload.ID)
			if !ok {
				return fail("not_found", fmt.Errorf("province not found"))
			}
			if req.Op == "get_province" {
				response.Data = province
			} else {
				response.Data = map[string]any{"provinceId": payload.ID, "precisionYears": 10, "records": s.simulation.OwnershipHistory(payload.ID)}
			}
		case "get_entity", "list_entities":
			var payload struct {
				Kind string `json:"kind"`
				ID   int    `json:"id"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			if req.Op == "get_entity" {
				record, ok := s.simulation.Entity(payload.Kind, payload.ID)
				if !ok {
					return fail("not_found", fmt.Errorf("entity not found; dynasty labels are not standalone entities"))
				}
				response.Data = record
			} else {
				response.Data = s.simulation.Entities(payload.Kind)
			}
		case "get_historical_layer":
			var payload struct {
				Year int `json:"year"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			layer, ok := s.simulation.HistoricalLayer(payload.Year)
			if !ok {
				return fail("not_found", fmt.Errorf("no retained historical layer for that year"))
			}
			response.Data = layer
		case "get_replay":
			response.Data = s.simulation.Replay()
		case "export":
			var payload struct {
				Directory string `json:"directory"`
			}
			if err := decodePayload(req.Payload, &payload); err != nil {
				return fail("invalid_arguments", err)
			}
			if payload.Directory == "" {
				return fail("invalid_arguments", fmt.Errorf("directory is required"))
			}
			directory, err := filepath.Abs(payload.Directory)
			if err != nil {
				return fail("invalid_arguments", err)
			}
			if err = WriteBundle(directory, s.world, s.surface, s.simulation); err != nil {
				return fail("export_failed", err)
			}
			response.Data = map[string]any{"directory": directory, "manifest": "manifest.json", "state": "state.json"}
		default:
			return fail("unknown_operation", fmt.Errorf("unknown operation %q", req.Op))
		}
	}
	response.OK = true
	if s.simulation != nil {
		year := s.simulation.Status().Year
		response.Year = &year
	}
	return response
}

// Serve only accepts a loopback listener. Requests are processed sequentially;
// one advance means one complete year, so a queued pause never waits for an
// arbitrary multi-year batch. There is no simulation clock or background run.
func Serve(ctx context.Context, listener net.Listener, session *Session) error {
	address, ok := listener.Addr().(*net.TCPAddr)
	if !ok || !address.IP.IsLoopback() {
		return fmt.Errorf("local protocol requires a loopback TCP listener")
	}
	defer listener.Close()
	session.trace = telemetry.Open("go-server")
	defer session.trace.Close()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			listener.Close()
		case <-done:
		}
	}()
	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		shutdown, err := serveConnection(ctx, conn, session)
		conn.Close()
		if shutdown {
			return nil
		}
		if ctx.Err() != nil {
			return nil
		}
		if err != nil {
			continue
		}
	}
}
func serveConnection(ctx context.Context, conn net.Conn, session *Session) (bool, error) {
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			conn.Close()
		case <-done:
		}
	}()
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 4096), 16*1024*1024)
	counter:=&timedWriter{writer:conn,enabled:session.trace!=nil}
	encoder := json.NewEncoder(counter)
	for scanner.Scan() {
		var req Request
		if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
			if err = encoder.Encode(Response{Schema: LocalSchema, Error: &ProtocolError{Code: "invalid_json", Message: err.Error()}}); err != nil {
				return false, err
			}
			continue
		}
		response := session.Handle(req)
		var encodeStart time.Time
		if session.trace != nil {encodeStart=time.Now();counter.elapsed=0;counter.bytes=0}
		if err := encoder.Encode(response); err != nil {
			return false, err
		}
		if session.trace!=nil { session.trace.Record("json",time.Since(encodeStart)-counter.elapsed,map[string]any{"op":req.Op,"bytes":counter.bytes,"socketWriteUs":counter.elapsed.Microseconds()}) }
		if req.Op == "shutdown" && response.OK {
			return true, nil
		}
	}
	return false, scanner.Err()
}

type timedWriter struct {writer io.Writer;enabled bool;elapsed time.Duration;bytes int}
func(w *timedWriter)Write(p []byte)(int,error){if !w.enabled{return w.writer.Write(p)};start:=time.Now();n,e:=w.writer.Write(p);w.elapsed+=time.Since(start);w.bytes+=n;return n,e}
