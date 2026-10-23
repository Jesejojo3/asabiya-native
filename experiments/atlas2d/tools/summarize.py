"""Offline analysis. Callback rates are never labeled as displayed FPS."""
import argparse
import json
import math
import re
from pathlib import Path
from presentation import presentation, utc_ms


def percentile(values, q):
    if not values:
        return None
    values = sorted(values)
    rank = (len(values) - 1) * q
    lo, hi = math.floor(rank), math.ceil(rank)
    return values[lo] + (values[hi] - values[lo]) * (rank - lo)


def read_jsonl(path):
    with Path(path).open(encoding='utf-8-sig') as f:
        return [json.loads(line) for line in f if line.strip()]


def hardware(environment, equipment):
    render = bool(re.search(r'Intel.*Iris.*Xe', environment.get('gpu',''), re.I)) and not environment.get('headless',True)
    inventory = any(re.search(r'Intel.*Iris.*Xe', g.get('Name',''), re.I) for g in equipment.get('gpu',[]))
    cpu = bool(re.search(r'i5-1340P',environment.get('cpu',''), re.I))
    return {'targetHardwareVerified': render and inventory and cpu,
            'active_renderer_iris_xe':render, 'windows_inventory_iris_xe':inventory,'cpu_i5_1340p':cpu,
            'definition':'Godot active GPU + Windows inventory + CPU identity; no performance certification'}


def summary(path):
    path = Path(path); rows = read_jsonl(path)
    environment = next(r for r in rows if r['kind'] == 'environment')
    ready = next((r for r in rows if r['kind'] == 'ready'),None)
    sample = next((r for r in rows if r['kind'] == 'sample_begin'),None)
    end = next((r for r in rows if r['kind'] == 'end'),None)
    atlas = environment.get('schema','').startswith('asabiya/atlas2d-measure-')
    if not ready or not ready.get('framebuffer_size') or (atlas and ready['framebuffer_size'] != ready.get('window_size')):
        raise ValueError('Framebuffer resolution not validated')
    if not atlas and ready['framebuffer_size'] != [1920,1080]:
        raise ValueError('Microprobe framebuffer resolution not validated')
    if atlas and (not sample or not end or not any(r['kind']=='verified_pause' and r.get('exact') and r.get('state_sha256') for r in rows)):
        raise ValueError('Incomplete capture / pause not verified')
    if any(r['kind']=='error' for r in rows) or (end and end.get('buffer_overflow')):
        raise ValueError('Runtime error or profiler buffer overflow')
    if sample and end and end['ticks_us'] <= sample['ticks_us']:
        raise ValueError('Invalid sample window')
    measured = [r for r in rows if not sample or sample['ticks_us'] <= r.get('ticks_us',0) <= end['ticks_us']]
    frames = [r.get('post_draw_interval_ms',r.get('frame_ms')) for r in measured if r['kind']=='frame']
    if any(not isinstance(v,(float,int)) or not math.isfinite(v) or v<=0 for v in frames):
        raise ValueError('Invalid post_draw intervals')
    if not frames and not (end and end.get('post_draw_callbacks',0)>0):
        raise ValueError('Missing callback samples or aggregate')
    seconds = (end['ticks_us']-sample['ticks_us'])/1e6 if sample else sum(frames)/1000
    callbacks = end.get('post_draw_callbacks',len(frames)) if end else len(frames)
    result = {'file':path.name,'environment':environment,'ready':ready,
              'sample_seconds':seconds,'sample_begin':sample,'end':end,
              'protocol':next((r for r in rows if r['kind']=='begin'),{}),
              'post_draw':{'callbacks':callbacks,'callbacks_per_second':callbacks/seconds,
                           'interval_ms_p50':percentile(frames,.5),'interval_ms_p95':percentile(frames,.95),
                           'interval_ms_p99':percentile(frames,.99),
                           'interval_ms_max':max(frames) if frames else end.get('post_draw_interval_max_ms'),
                           'definition':'Godot frame_post_draw callbacks; not displayed FPS'},
              'years_per_second':(end['year']-sample['year'])/seconds if sample else None}
    for kind in ('selection_local','selection_query','selection_post_draw','map_post_draw','selection_present','map_present','year_request_to_receive','slow_poll'):
        values = [r['ms'] for r in measured if r['kind']==kind]
        result[kind+'_ms']={'samples':len(values),'p50':percentile(values,.5),'p95':percentile(values,.95)}
    for field in ('projection_ms','upload_ms'):
        values = [r[field] for r in measured if r['kind']=='map_update']
        result[field]={'samples':len(values),'p50':percentile(values,.5),'p95':percentile(values,.95)}
    equipment_path=path.parent/'equipo.json'
    equipment=json.loads(equipment_path.read_text(encoding='utf-8-sig')) if equipment_path.exists() else {}
    result['hardware']=hardware(environment,equipment)
    telemetry_path=path.with_suffix('.telemetry.jsonl')
    telemetry=read_jsonl(telemetry_path) if telemetry_path.exists() else []
    result['presentation']=presentation(path.with_suffix('.presentmon.csv'),environment,sample,end,telemetry,percentile)
    pm_logs=[path.with_suffix('.presentmon.'+stream+'.log') for stream in ('stdout','stderr')]
    if any(p.exists() and re.search(r'(?:lost|dropped)\s+(?:events\s*[:=]?\s*)?[1-9]|[1-9]\d*\s+(?:events\s+)?lost',p.read_text(errors='replace'),re.I) for p in pm_logs):
        result['presentation'].update(valid=False,reason='PresentMon reported lost events; inspect logs')
    if telemetry:
        window = [r for r in telemetry if r.get('kind')=='sample' and sample['utc_unix_ms'] <= utc_ms(r['utc']) <= end['utc_unix_ms']]
        result['telemetry']={'sample_count':len(window),'all_phases_sample_count':sum(r.get('kind')=='sample' for r in telemetry),
                             'poll_work_ms_p95':percentile([r['poll_work_ms'] for r in window if r.get('poll_work_ms') is not None],.95),
                             'max_sample_gap_s':max((b['elapsed_s']-a['elapsed_s'] for a,b in zip(window,window[1:])),default=None),
                             'unfocused_samples':sum(not r.get('window',{}).get('focused',False) for r in window),
                             'minimized_samples':sum(r.get('window',{}).get('minimized',False) for r in window)}
        for role in ('godot','go','collector','presentmon'):
            good = [r[role] for r in window if r[role]['status']=='ok']
            result['telemetry'][role]={'valid_samples':len(good),'missing_samples':len(window)-len(good),
                'working_set_peak_bytes':max((r['working_set_bytes'] for r in good),default=None),
                'private_peak_bytes':max((r['private_bytes'] for r in good),default=None),
                'cpu_machine_percent_p50':percentile([r['cpu_machine_percent'] for r in good if r.get('cpu_machine_percent') is not None],.5),
                'cpu_one_core_percent_p95':percentile([r['cpu_one_core_percent'] for r in good if r.get('cpu_one_core_percent') is not None],.95)}
    legacy=path.with_suffix('.memory.jsonl')
    if legacy.exists():
        memory=read_jsonl(legacy)
        result['legacy_memory']={'samples':len(memory),'go_pid_unknown':sum(r.get('go_pid',0)<=0 for r in memory),
                                 'go_zero_with_pid':sum(r.get('go_pid',0)>0 and r.get('go_bytes',0)==0 for r in memory),
                                 'warning':'Legacy zero conflates undiscovered, unavailable and exited; not valid RAM samples.'}
    for field in ("main_ms", "render_cpu_ms", "render_gpu_ms"):
        values = [r[field] for r in measured if r["kind"] == "frame" and isinstance(r.get(field), (int, float))]
        result[field] = {"samples":len(values), "p50":percentile(values,.5), "p95":percentile(values,.95), "p99":percentile(values,.99)}
    result["main_thread_ticks_over_20ms"] = sum(r["kind"] == "slow_tick" for r in measured)
    return result


def comparison(results):
    groups={}
    for r in results:
        e=r['environment'];ready=r['ready'];mode=e.get('instrumentation','legacy')
        key=json.dumps({'framebuffer':ready['framebuffer_size'],'zoom':ready.get('zoom_multiplier'),
                        'sample_start_year':(r.get('sample_begin') or {}).get('year'),
                        'source_commit':e.get('build',{}).get('commit'),
                        'source_tree_hash':e.get('build',{}).get('experimentTreeSHA256'),
                        'world_sha':ready.get('world_sha256'),'config':ready.get('world_config'),
                        'prepared_sha':ready.get('state_sha256'),'layer':ready.get('layer'),
                        'history_seed':ready.get('history_seed'),'pan':e.get('camera_pan'),
                        'selection':e.get('automated_selection'),'active':e.get('active',(r['years_per_second'] or 0)>0),
                        'cpu':e.get('cpu'),'gpu':e.get('gpu'),'os':e.get('os'),'renderer':e.get('renderer'),
                        'godot':e.get('godot'),'vsync':e.get('vsync_requested'),
                        'duration_seconds':r.get('protocol',{}).get('duration_seconds'),
                        'warmup_seconds':r.get('protocol',{}).get('warmup_seconds')},sort_keys=True)
        groups.setdefault(key,{}).setdefault(mode,[]).append(r)
    output=[]
    for key,modes in groups.items():
        entry={'scenario':json.loads(key),'modes':{}}
        for mode,rs in modes.items():
            values=[r['post_draw']['callbacks_per_second'] for r in rs]
            displays=[r['presentation'].get('displayed_events_per_second') for r in rs if r['presentation']['valid']]
            entry['modes'][mode]={'repetitions':len(rs),'post_draw_rate_median':percentile(values,.5),'post_draw_rate_range':[min(values),max(values)],
                                 'years_per_second_median':percentile([r['years_per_second'] for r in rs if r['years_per_second'] is not None],.5),
                                 'valid_display_repetitions':len(displays),'displayed_rate_median':percentile(displays,.5)}
        rates={m:v['post_draw_rate_median'] for m,v in entry['modes'].items()}
        entry['callback_rate_change_percent']={}
        for before,after in [('baseline','minimal'),('minimal','detailed')]:
            if before in rates and after in rates:
                entry['callback_rate_change_percent'][before+'->'+after]=100*(rates[after]/rates[before]-1)
        entry['interpretation']='Paired scenario comparisons, not proof of profiler causality; assess all three repetitions and thermal/order effects.'
        output.append(entry)
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('captures',nargs='+');parser.add_argument('--out');args=parser.parse_args()
    results=[summary(p) for p in args.captures]
    content=json.dumps({'captures':results,'comparisons':comparison(results)},indent=2,allow_nan=False)+'\n'
    if args.out:Path(args.out).write_text(content,encoding='utf-8')
    print(content)
