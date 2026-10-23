package main

import "os"

// On Windows FindProcess opens a stable process handle and Wait waits on that
// handle, including a non-child process. This avoids a PID-reuse polling race.
func stopWhenParentExits(pid int, stop func()) {
	p, err := os.FindProcess(pid)
	if err != nil {
		stop()
		return
	}
	defer p.Release()
	_, _ = p.Wait()
	stop()
}
