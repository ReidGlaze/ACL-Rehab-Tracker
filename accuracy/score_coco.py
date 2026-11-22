"""Scores a knee_pose_run result against the COCO hand labels.

    python3 accuracy/score_coco.py accuracy/results/coco.json

The estimator's leg is matched to the labelled leg whose knee is nearest, because left and right
labels are unreliable in side views. Error is estimator angle minus labelled angle, in degrees.
"""
import json,math,statistics,sys
import os
truth={t['fixture']:t for t in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'fixtures','coco_truth.json')))}
rows=json.load(open(sys.argv[1])); errs=[];e3=[];out=[]
nf=0
for r in rows:
    t=truth[r['file']]
    if not r['found']: nf+=1; out.append((r['file'],'NOT FOUND')); continue
    kx,ky=r['knee']['x']*t['w'],r['knee']['y']*t['h']
    name,leg=min(t['legs'].items(),key=lambda kv: math.hypot(kv[1]['knee'][0]-kx,kv[1]['knee'][1]-ky))
    dist=math.hypot(leg['knee'][0]-kx,leg['knee'][1]-ky)/max(t['w'],t['h'])
    e=r['angle']-leg['flexion']; errs.append((e,leg['flexion'],r['confidence'],dist,r['file']))
    if r.get('angle3D') is not None: e3.append(r['angle3D']-leg['flexion'])
ab=[abs(e[0]) for e in errs]
def summ(label,a):
    a=sorted(a); n=len(a)
    if not n: return
    print(f"{label}: n={n} median {statistics.median(a):.1f} mean {sum(a)/n:.1f} p90 {a[int(n*.9)-1]:.1f} max {a[-1]:.1f} | within5 {sum(x<=5 for x in a)/n:.0%} within10 {sum(x<=10 for x in a)/n:.0%}")
print('not found',nf,'of',len(rows))
summ('2D abs error (all)',ab)
summ('2D, confidence>=0.3',[abs(e[0]) for e in errs if e[2]>=0.3])
summ('2D, confidence>=0.5',[abs(e[0]) for e in errs if e[2]>=0.5])
summ('3D abs error',[abs(x) for x in e3])
for lo,hi in [(0,30),(30,60),(60,90),(90,120),(120,181)]:
    summ(f' truth {lo}-{hi}',[abs(e[0]) for e in errs if lo<=e[1]<hi])
print('signed mean',round(sum(e[0] for e in errs)/len(errs),1))
print('worst:'); [print('  ',round(e[0]),'truth',round(e[1]),'conf',round(e[2],2),'kneeDist',round(e[3],3),e[4]) for e in sorted(errs,key=lambda e:-abs(e[0]))[:12]]
