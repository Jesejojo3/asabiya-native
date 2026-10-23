//go:build !windows

package main

// Parent ownership is a Windows-only packaging feature. Diagnostic builds on
// other operating systems retain the explicit shutdown/context lifecycle.
func stopWhenParentExits(_ int, _ func()) {}
