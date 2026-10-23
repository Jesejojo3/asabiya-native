#!/usr/bin/env python3
"""TEST DOUBLE of the Go engine bridge (protocol asabiya-bridge/v1).

Used only by the client test suite to exercise the stdio plumbing, frame
decoding and the renderers of historical layers. It is NOT a simulation and is
never shipped or launched by the application: the real implementation belongs
to the Go engine (see docs/client/API_REQUESTS.md).

Usage: mock_bridge.py --snapshot WORLD.asw --stdio
"""
import base64, json, struct, sys
from collections import deque


def load_land(path):
    b = open(path, "rb").read()
    hl = struct.unpack("<I", b[8:12])[0]
    h = json.loads(b[12:12 + hl])
    d = b[12 + hl:]
    lay = {l["name"]: l for l in h["layers"]}
    l = lay["land"]
    land = d[l["offset"]:l["offset"] + l["bytes"]]
    return h["world"]["width"], h["world"]["height"], land


def b64(fmt, values):
    return base64.b64encode(struct.pack("<%d%s" % (len(values), fmt), *values)).decode()


class Mock:
    def __init__(self, snapshot):
        self.w, self.h, self.land = load_land(snapshot)
        self.n = self.w * self.h
        self.year = -3000
        land_cells = [i for i in range(self.n) if self.land[i] == 1]
        # three fixed seeds spread over the land list (deterministic)
        self.seeds = [land_cells[len(land_cells) * k // 7] for k in (2, 3, 5)]
        self.size = 40

    def nb(self, i):
        x, y = i % self.w, i // self.w
        out = [y * self.w + (x - 1) % self.w, y * self.w + (x + 1) % self.w]
        if y > 0: out.append(i - self.w)
        if y < self.h - 1: out.append(i + self.w)
        return out

    def grow(self):
        owner = [-1] * self.n
        q = deque()
        for s, c in enumerate(self.seeds):
            owner[c] = s
            q.append(c)
        count = [1, 1, 1]
        while q:
            i = q.popleft()
            s = owner[i]
            if count[s] >= self.size:
                continue
            for j in self.nb(i):
                if self.land[j] == 1 and owner[j] < 0:
                    owner[j] = s
                    count[s] += 1
                    q.append(j)
        return owner

    def frame(self):
        owner = self.grow()
        people = [(o % 2) if o >= 0 else -1 for o in owner]
        religion = [0 if o >= 0 else -1 for o in owner]
        pop = [1500.0 if o >= 0 else 0.0 for o in owner]
        front = [i for i in range(self.n) if owner[i] == 0 and any(owner[j] == 1 for j in self.nb(i))]
        sets = []
        for k, c in enumerate(self.seeds):
            sets.append({"id": k + 1, "cell": c, "name": "Ciudad %d" % (k + 1), "tier": [4, 3, 1][k],
                         "population": [150000, 40000, 3000][k], "founded": -3500,
                         "state": k, "era": 2, "features": {"walls": k < 2, "castle": k == 0, "temple": True,
                                                            "market": k < 2, "port": k == 0}})
        events = [{"year": self.year, "kind": "founding", "text": "Fundación de Ciudad 1", "cell": self.seeds[0]}]
        return {
            "year": self.year,
            "systems": ["states", "peoples", "religions", "population", "settlements", "wars", "events", "routes"],
            "cells": {"owner": b64("i", owner), "people": b64("i", people), "religion": b64("i", religion),
                      "population": b64("f", pop)},
            "states": [{"id": s, "name": "Reino %d" % s, "rgb": [[180, 60, 50], [60, 110, 170], [200, 170, 70]][s],
                        "ruler": "Gobernante %d" % s, "founded": -3500, "history": ["Fundado en 3500 a. C."]}
                       for s in range(3)],
            "peoples": [{"id": p, "name": "Pueblo %d" % p, "rgb": [[120, 160, 90], [160, 110, 160]][p], "family": p}
                        for p in range(2)],
            "religions": [{"id": 0, "name": "Culto 0", "rgb": [220, 200, 120]}],
            "settlements": sets,
            "events": events,
            "wars": [{"id": 1, "a": 0, "b": 1, "started": self.year, "front": front[:20]}],
            "routes": [{"id": 1, "cells": [self.seeds[0], self.seeds[1]], "volume": 0.7}],
        }


def main():
    args = sys.argv[1:]
    snap = args[args.index("--snapshot") + 1]
    m = Mock(snap)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        req = json.loads(line)
        rid, cmd = req.get("id"), req.get("cmd")
        if cmd == "hello":
            resp = {"id": rid, "ok": req.get("protocol") == "asabiya-bridge/v1", "engine": "mock", "canAdvance": True}
        elif cmd == "open":
            resp = {"id": rid, "ok": True, "year": m.year}
        elif cmd == "frame":
            resp = {"id": rid, "ok": True, "frame": m.frame()}
        elif cmd == "advance":
            m.year += int(req.get("years", 1))
            m.size += 15
            resp = {"id": rid, "ok": True, "frame": m.frame()}
        elif cmd == "close":
            break
        else:
            resp = {"id": rid, "ok": False, "error": "unknown command"}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
