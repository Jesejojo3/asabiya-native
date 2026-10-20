package sim

import (
	"hash"
	"sync"
)

const digestBufferSize = 1 << 20

// This pool contains encoding scratch, never SHA state or cached causal data.
// Each active digest owns a distinct set, including simultaneous read queries.
var digestBufferPool = sync.Pool{New: func() any {
	buffers := new([3][]byte)
	for i := range buffers {
		buffers[i] = make([]byte, 0, digestBufferSize)
	}
	return buffers
}}

// digestPipeline overlaps canonical encoding with a single ordered SHA writer.
// Three fixed buffers bound memory and provide backpressure. No hash state or
// causal field is cached, and no buffer is reused until Write has returned.
type digestPipeline struct {
	pending  chan []byte
	free     chan []byte
	done     chan struct{}
	finished bool
	pooled   *[3][]byte
}

func newPooledDigestPipeline(d hash.Hash) (*digestPipeline, []byte) {
	buffers := digestBufferPool.Get().(*[3][]byte)
	p := startDigestPipeline(d, buffers[1], buffers[2])
	p.pooled = buffers
	return p, buffers[0]
}

func newDigestPipeline(d hash.Hash, capacity int) *digestPipeline {
	return startDigestPipeline(d, make([]byte, 0, capacity), make([]byte, 0, capacity))
}

func startDigestPipeline(d hash.Hash, first, second []byte) *digestPipeline {
	p := &digestPipeline{
		pending: make(chan []byte, 2),
		free:    make(chan []byte, 3),
		done:    make(chan struct{}),
	}
	p.free <- first
	p.free <- second
	go func() {
		defer close(p.done)
		for b := range p.pending {
			d.Write(b)
			p.free <- b[:0]
		}
	}()
	return p
}

func (p *digestPipeline) submit(b []byte) []byte {
	p.pending <- b
	return <-p.free
}

func (p *digestPipeline) finish() {
	if !p.finished {
		p.finished = true
		close(p.pending)
		<-p.done
		if p.pooled != nil {
			digestBufferPool.Put(p.pooled)
		}
	}
}
