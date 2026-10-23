"""PresentMon 2.3 display-event analysis, independent of Godot post_draw callbacks."""
import csv
import math
from datetime import datetime
from pathlib import Path


def utc_ms(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp() * 1000


def presentation(path, environment, sample, end, telemetry, percentile):
    result = {'valid': False, 'source': 'PresentMon 2.3.0 ETW display events',
              'limitation': 'Software-visible display events; no optical scanout measurement.'}
    if not Path(path).exists():
        return dict(result, reason='not captured (baseline or legacy capture)')
    try:
        anchors = [r for r in telemetry if r.get('kind') == 'sample']
        if len(anchors) < 2:
            raise ValueError('missing QPC/UTC anchors')
        frequency = anchors[0]['qpc_frequency']
        if any(r['qpc_frequency'] != frequency for r in anchors):
            raise ValueError('QPC frequency changed')
        offsets = [utc_ms(r['utc']) - (r['qpc'] + r['qpc_after_utc']) / 2 / frequency * 1000 for r in anchors]
        drift = max(offsets) - min(offsets)
        clock_span = end['utc_unix_ms'] - sample['utc_unix_ms']
        monotonic_span = (end['ticks_us'] - sample['ticks_us']) / 1000
        if drift > 5 or abs(clock_span - monotonic_span) > 5:
            raise ValueError('UTC/QPC or Godot clock drift >5 ms')
        uncertainty = max((r['qpc_after_utc'] - r['qpc']) / frequency * 1000 / 2 for r in anchors)
        uncertainty += max((r.get('clock_ticks_us_after', r['ticks_us']) - r['ticks_us']) / 1000 for r in (sample, end)) + drift
        if uncertainty > 5:
            raise ValueError('clock alignment uncertainty >5 ms')
        offset = sorted(offsets)[len(offsets)//2]
        begin_ms, end_ms = sample['utc_unix_ms'] - offset, end['utc_unix_ms'] - offset
        streams = {}; submitted = 0; not_displayed = 0
        with Path(path).open(encoding='utf-8-sig', newline='') as f:
            reader = csv.DictReader(f)
            required = {'ProcessID', 'SwapChainAddress', 'CPUStartQPC', 'DisplayLatency', 'DisplayedTime'}
            if not required.issubset(reader.fieldnames or []):
                raise ValueError('missing PresentMon QPC/display columns')
            for row in reader:
                if int(row['ProcessID']) != int(environment['pid']):
                    raise ValueError('PresentMon PID mismatch')
                cpu_ms = int(row['CPUStartQPC']) / frequency * 1000
                if begin_ms <= cpu_ms < end_ms:
                    submitted += 1
                    if row['DisplayedTime'] in ('NA', ''):
                        not_displayed += 1
                if row['DisplayedTime'] in ('NA', '') or row['DisplayLatency'] in ('NA', ''):
                    continue
                latency = float(row['DisplayLatency']); displayed = float(row['DisplayedTime'])
                if not all(math.isfinite(v) and v >= 0 for v in (latency, displayed)):
                    raise ValueError('invalid display metric')
                timestamp = cpu_ms + latency
                streams.setdefault(row['SwapChainAddress'], []).append(timestamp)
        relevant = {k: sorted(set(v)) for k, v in streams.items() if any(begin_ms <= t < end_ms for t in v)}
        if len(relevant) != 1:
            raise ValueError('expected exactly one displayed swap chain; inspect raw CSV')
        chain, timestamps = next(iter(relevant.items()))
        if not any(t < begin_ms for t in timestamps) or not any(t >= end_ms for t in timestamps):
            raise ValueError('display trace does not bracket the sample window')
        selected = [t for t in timestamps if begin_ms <= t < end_ms]
        intervals = [b-a for a,b in zip(selected, selected[1:])]
        if len(intervals) < 2:
            raise ValueError('insufficient displayed events')
        return dict(result, valid=True, reason=None, swap_chain=chain,
                    clock_alignment_uncertainty_ms=uncertainty, clock_drift_ms=drift,
                    displayed_events=len(selected), displayed_events_per_second=len(selected)*1000/(end_ms-begin_ms),
                    display_interval_ms_p50=percentile(intervals,.5), display_interval_ms_p95=percentile(intervals,.95),
                    display_interval_ms_p99=percentile(intervals,.99), display_interval_ms_max=max(intervals),
                    display_intervals_above_33_333ms_percent=100*sum(v>1000/30 for v in intervals)/len(intervals),
                    boundary_gaps_ms=[selected[0]-begin_ms,end_ms-selected[-1]],
                    boundary_policy='percentiles use pairs inside window; boundary gaps reported separately',
                    submitted_frames=submitted, not_displayed_frames=not_displayed)
    except (ValueError, KeyError, TypeError, OverflowError) as e:
        return dict(result, reason=str(e))
