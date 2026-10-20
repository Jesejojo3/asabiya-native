package telemetry
import ("bufio";"encoding/json";"os";"path/filepath";"runtime";"time";"fmt")
// Trace is single-owner, bounded and opt-in. Each process/component owns its file.
type Trace struct { file *os.File; writer *bufio.Writer; start time.Time; records int }
func Open(component string) *Trace {
 dir:=os.Getenv("ASABIYA_THROUGHPUT_DIR");if dir=="" {return nil}
 if os.MkdirAll(dir,0700)!=nil{return nil}
 f,e:=os.Create(filepath.Join(dir,fmt.Sprintf("%s-%d.jsonl",component,os.Getpid())));if e!=nil{return nil}
 t:=&Trace{file:f,writer:bufio.NewWriterSize(f,65536),start:time.Now()}
 t.Record("environment",0,map[string]any{"go":runtime.Version(),"os":runtime.GOOS,"arch":runtime.GOARCH,"gomaxprocs":runtime.GOMAXPROCS(0),"cpu":os.Getenv("PROCESSOR_IDENTIFIER")});return t
}
func(t *Trace) Record(stage string, elapsed time.Duration, fields map[string]any) {
 if t==nil||t.records>=4096{return};t.records++
 fields["stage"]=stage;fields["elapsedUs"]=elapsed.Microseconds();fields["ticksUs"]=time.Since(t.start).Microseconds()
 _=json.NewEncoder(t.writer).Encode(fields);if t.records%32==0 {_=t.writer.Flush()}
}
func(t *Trace) Close(){if t!=nil{_=t.writer.Flush();_=t.file.Close()}}
