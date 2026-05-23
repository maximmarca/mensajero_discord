package main

import (
	"fmt"
	"strings"
	"testing"
)

func TestChunkContentShortNoSplit(t *testing.T) {
	r := chunkContent("hola maxi --fer", 1500)
	if len(r) != 1 {
		t.Fatalf("expected 1 chunk, got %d", len(r))
	}
	if !strings.HasSuffix(r[0], "--fer") {
		t.Errorf("expected suffix preserved, got %q", r[0])
	}
	if strings.HasPrefix(r[0], "[CHUNK") {
		t.Errorf("short content should not be prefixed, got %q", r[0])
	}
}

func TestChunkContentLongSplitsAndPreservesSignature(t *testing.T) {
	lines := make([]string, 0, 60)
	for i := 0; i < 60; i++ {
		lines = append(lines, fmt.Sprintf("linea %02d con suficiente texto para llenar bastante este renglon", i))
	}
	body := strings.Join(lines, "\n")
	long := body + " --maxi"

	r := chunkContent(long, 500)
	if len(r) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(r))
	}

	for i, c := range r {
		if !strings.HasPrefix(c, fmt.Sprintf("[CHUNK %d/%d] ", i+1, len(r))) {
			t.Errorf("chunk %d missing/wrong prefix: %q", i, c[:30])
		}
		if !strings.HasSuffix(c, "--maxi") {
			t.Errorf("chunk %d does not end with --maxi: %q", i, c[max0(0, len(c)-20):])
		}
		if len(c) > 500 {
			t.Errorf("chunk %d exceeds budget: len=%d", i, len(c))
		}
	}
}

func TestChunkContentNoSignatureLongCutsHard(t *testing.T) {
	noSig := strings.Repeat("a", 1800)
	r := chunkContent(noSig, 500)
	if len(r) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(r))
	}
	totalLen := 0
	for i, c := range r {
		if !strings.HasPrefix(c, fmt.Sprintf("[CHUNK %d/%d] ", i+1, len(r))) {
			t.Errorf("chunk %d missing prefix", i)
		}
		if len(c) > 500 {
			t.Errorf("chunk %d exceeds budget: len=%d", i, len(c))
		}
		body := strings.TrimPrefix(c, fmt.Sprintf("[CHUNK %d/%d] ", i+1, len(r)))
		totalLen += len(body)
	}
	if totalLen != 1800 {
		t.Errorf("reassembled length mismatch: got %d, want 1800", totalLen)
	}
}

func TestChunkContentNewlineBoundaryPreferred(t *testing.T) {
	input := strings.Repeat("aaaa\n", 100) + "--fer" // 505 chars
	r := chunkContent(input, 80)
	if len(r) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(r))
	}
	for i, c := range r {
		prefix := fmt.Sprintf("[CHUNK %d/%d] ", i+1, len(r))
		stripped := strings.TrimSuffix(c, "\n--fer")
		body := strings.TrimPrefix(stripped, prefix)
		for j, part := range strings.Split(body, "\n") {
			if part == "" {
				continue
			}
			if part != "aaaa" {
				t.Errorf("chunk %d part %d: cut mid-line, expected complete 'aaaa' unit, got %q", i, j, part)
			}
		}
	}
}

func TestChunkContentSignatureAlsoOnLastChunk(t *testing.T) {
	r := chunkContent(strings.Repeat("x", 3000)+" --fer", 1500)
	if len(r) < 2 {
		t.Fatalf("expected splits, got %d", len(r))
	}
	for i, c := range r {
		if !strings.HasSuffix(c, "--fer") {
			t.Errorf("chunk %d missing signature: ends with %q", i, c[max0(0, len(c)-15):])
		}
	}
}

func max0(a, b int) int {
	if a > b {
		return a
	}
	return b
}
