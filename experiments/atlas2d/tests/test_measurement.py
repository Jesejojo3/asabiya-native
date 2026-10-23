import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from summarize import summary, percentile, hardware, comparison
from presentation import presentation

class MeasurementTests(unittest.TestCase):
    def test_adapter_verification_uses_active_renderer(self):
        env={'cpu':'Intel i5-1340P','gpu':'Intel(R) Iris(R) Xe Graphics','headless':False}
        inventory={'gpu':[{'Name':env['gpu']}]}
        self.assertTrue(hardware(env,inventory)['targetHardwareVerified'])
        self.assertFalse(hardware(dict(env,gpu='llvmpipe'),inventory)['targetHardwareVerified'])
        self.assertFalse(hardware(dict(env,headless=True),inventory)['targetHardwareVerified'])
        self.assertFalse(hardware(env,{})['targetHardwareVerified'])

    def test_window_excludes_warmup_and_after_end_and_keeps_stalls(self):
        rows=[{'kind':'environment','schema':'asabiya/atlas2d-measure-v2'},
              {'kind':'ready','framebuffer_size':[1920,1080],'window_size':[1920,1080]},
              {'kind':'sample_begin','ticks_us':100,'year':1000},
              {'kind':'frame','ticks_us':99,'post_draw_interval_ms':99999},
              {'kind':'frame','ticks_us':101,'post_draw_interval_ms':7.1},
              {'kind':'frame','ticks_us':200,'post_draw_interval_ms':7100},
              {'kind':'end','ticks_us':10000100,'year':1033},
              {'kind':'frame','ticks_us':10000101,'post_draw_interval_ms':99999},
              {'kind':'verified_pause','exact':True,'state_sha256':'abc'}]
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'run.jsonl'
            path.write_text('\n'.join(json.dumps(r) for r in rows))
            result=summary(path)
            self.assertEqual(result['post_draw']['callbacks'],2)
            self.assertEqual(result['post_draw']['interval_ms_max'],7100)
            self.assertEqual(result['years_per_second'],3.3)
            self.assertFalse(result['presentation']['valid'])
            rows[6]['buffer_overflow']=True
            path.write_text('\n'.join(json.dumps(r) for r in rows))
            with self.assertRaises(ValueError): summary(path)

    def test_presentmon_distinguishes_submitted_and_displayed(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'run.csv'
            fields=['ProcessID','SwapChainAddress','CPUStartQPC','DisplayLatency','DisplayedTime']
            def write(extra=None):
                with path.open('w',newline='') as f:
                    w=csv.DictWriter(f,fieldnames=fields);w.writeheader()
                    for t in range(900,2201,100):
                        w.writerow(dict(zip(fields,[17,'0x1',t,0,100])))
                    w.writerow(dict(zip(fields,[17,'0x1',1501,'NA','NA'])))
                    if extra:w.writerow(dict(zip(fields,extra)))
            write()
            sample={'ticks_us':0,'utc_unix_ms':1000}
            end={'ticks_us':1000000,'utc_unix_ms':2000}
            telemetry=[{'kind':'sample','qpc':t,'qpc_after_utc':t,'qpc_frequency':1000,'utc':f'1970-01-01T00:00:0{t//1000}.000Z'} for t in (0,3000)]
            result=presentation(path,{'pid':17},sample,end,telemetry,percentile)
            self.assertTrue(result['valid'],result)
            self.assertEqual(result['displayed_events_per_second'],10)
            self.assertEqual(result['not_displayed_frames'],1)
            self.assertEqual(result['display_interval_ms_p95'],100)
            write([18,'0x1',1600,0,100])
            self.assertIn('PID mismatch',presentation(path,{'pid':17},sample,end,telemetry,percentile)['reason'])
            write([17,'0x2',1600,0,100])
            self.assertFalse(presentation(path,{'pid':17},sample,end,telemetry,percentile)['valid'])
            write();telemetry[1]['utc']='1970-01-01T00:00:03.020Z'
            self.assertIn('drift',presentation(path,{'pid':17},sample,end,telemetry,percentile)['reason'])

    def test_minimal_aggregate_and_repetitions(self):
        base={'environment':{'instrumentation':'minimal','active':False},'ready':{'framebuffer_size':[1920,1080]},
              'sample_begin':{'year':1000},'post_draw':{'callbacks_per_second':100},'years_per_second':0,'presentation':{'valid':False}}
        results=comparison([base]*3)
        self.assertEqual(results[0]['modes']['minimal']['repetitions'],3)

if __name__=='__main__':unittest.main()
