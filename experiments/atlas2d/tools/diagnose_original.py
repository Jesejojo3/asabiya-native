"""Read-only, reproducible audit of the owner's original Windows ZIP."""
import argparse
import hashlib
import json
import statistics
import zipfile
from datetime import datetime
from pathlib import Path

EXPECTED='0683f81ed189463d133c25f943e87fd3d7327c57b17d6be2975086f597648190'

def diagnose(path):
    data=Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest()!=EXPECTED:
        raise ValueError('Original ZIP SHA256 mismatch')
    result={'archive_sha256':EXPECTED,'files':{},'captures':[]}
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.endswith('/'):continue
            result['files'][name]=hashlib.sha256(z.read(name)).hexdigest()
        for name in sorted(z.namelist()):
            if not name.endswith('.jsonl') or '.memory.' in name:continue
            rows=[json.loads(line) for line in z.read(name).decode('utf-8-sig').splitlines() if line.strip()]
            one=lambda kind:next(r for r in rows if r['kind']==kind)
            ready,sample,end,verified=[one(k) for k in ('ready','sample_begin','end','verified_pause')]
            environment=one('environment');seconds=(end['ticks_us']-sample['ticks_us'])/1e6
            frames=[r for r in rows if r['kind']=='frame' and sample['ticks_us']<=r['ticks_us']<=end['ticks_us']]
            mem=[json.loads(line) for line in z.read(name.replace('.jsonl','.memory.jsonl')).decode('utf-8-sig').splitlines() if line.strip()]
            dt=lambda r:datetime.fromisoformat(r['utc'].replace('Z','+00:00'))
            gaps=[(dt(b)-dt(a)).total_seconds() for a,b in zip(mem,mem[1:])]
            result['captures'].append({'file':Path(name).name,'gpu':environment['gpu'],'cpu':environment['cpu'],
                'source_commit':environment['build']['commit'],'prepared_year':ready['year'],
                'prepared_world_sha256':ready['world_sha256'],'prepared_state_sha256':ready['state_sha256'],
                'verified_pause':verified,'sample_seconds':seconds,'sample_begin_year':sample['year'],'end_year':end['year'],
                'years_per_second':(end['year']-sample['year'])/seconds,
                'post_draw_callbacks':len(frames),'post_draw_callbacks_per_second':len(frames)/seconds,
                'callback_gaps_above_1s':[{'ticks_us':r['ticks_us'],'interval_ms':r['frame_ms']} for r in frames if r['frame_ms']>1000],
                'memory_samples':len(mem),'go_pid_unknown':sum(r['go_pid']==0 for r in mem),
                'go_zero_with_known_pid':sum(r['go_pid']>0 and r['go_bytes']==0 for r in mem),
                'memory_interval_median_s':statistics.median(gaps),'memory_interval_max_s':max(gaps),
                'presentation':'unavailable: no ETW/display events in original archive'})
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('archive');p.add_argument('--out');args=p.parse_args()
    content=json.dumps(diagnose(args.archive),indent=2,allow_nan=False)+'\n'
    if args.out:Path(args.out).write_text(content,encoding='utf-8')
    print(content)
