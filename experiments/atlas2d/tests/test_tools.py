import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from stage import ROOT, SHARED, stage
from summarize import percentile, summary

class ToolsTests(unittest.TestCase):
    def test_staging_keeps_consumed_adapters_identical(self):
        with tempfile.TemporaryDirectory() as directory:
            project = stage(directory)
            manifest = json.loads((project / "build-manifest.json").read_text())
            for name in SHARED:
                source = ROOT / "client/godot/scripts" / name
                self.assertEqual(source.read_bytes(), (project / "shared" / source.name).read_bytes())
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), manifest["sharedAdaptersSHA256"][str(source.relative_to(ROOT))])
    def test_percentiles_and_incomplete_capture(self):
        self.assertEqual(percentile([1, 3, 5, 7], .5), 4)
        self.assertAlmostEqual(percentile([1, 3, 5, 7], .95), 6.7)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "raw.jsonl"
            rows = [{"kind":"environment", "schema":"asabiya/atlas2d-measure-v1"}, {"kind":"frame", "frame_ms":20,"ticks_us":20}]
            path.write_text("\n".join(json.dumps(r) for r in rows))
            with self.assertRaises(ValueError):
                summary(path)
            rows += [{"kind":"ready","framebuffer_size":[1920,1080],"window_size":[1920,1080]}, {"kind":"sample_begin","ticks_us":10,"year":0}, {"kind":"end","ticks_us":1000010,"year":2}, {"kind":"verified_pause","exact":True,"state_sha256":"abc"}]
            path.write_text("\n".join(json.dumps(r) for r in rows))
            result = summary(path)
            self.assertEqual(result["post_draw"]["interval_ms_p50"],20)
            self.assertNotIn("fps_p50",result)
            self.assertEqual(result["years_per_second"],2)
            self.assertEqual(result["main_ms"]["samples"],0)
            rows[1]["main_ms"]=1.5
            rows.append({"kind":"slow_tick","ticks_us":20,"total_ms":25})
            path.write_text("\n".join(json.dumps(r) for r in rows))
            result = summary(path)
            self.assertEqual(result["main_ms"]["p50"],1.5)
            self.assertEqual(result["main_thread_ticks_over_20ms"],1)
    def test_stage_rejects_source_destination(self):
        with self.assertRaises(ValueError): stage(ROOT / "experiments/atlas2d")

if __name__ == "__main__": unittest.main()
