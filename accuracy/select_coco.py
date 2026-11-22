"""Builds the public accuracy set: single-person COCO val2017 photos with hand-labelled hip, knee and
ankle, spread across knee angles. Needs person_keypoints_val2017.json from
http://images.cocodataset.org/annotations/annotations_trainval2017.zip

    python3 accuracy/select_coco.py /path/to/person_keypoints_val2017.json
"""
import json,math,random,collections,urllib.request,os,sys
random.seed(7)
ANNOTATIONS=sys.argv[1] if len(sys.argv)>1 else 'person_keypoints_val2017.json'
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),'fixtures','coco')
d=json.load(open(ANNOTATIONS))
imgs={i['id']:i for i in d['images']}
by=collections.defaultdict(list)
for a in d['annotations']: by[a['image_id']].append(a)
def flex(k,hi,ki,ai,w,h):
    pts=[]
    for j in (hi,ki,ai):
        x,y,v=k[3*j:3*j+3]
        if v!=2: return None
        pts.append((x,y))
    (hx,hy),(kx,ky),(ax,ay)=pts
    v1=(hx-kx,hy-ky); v2=(ax-kx,ay-ky); l1=math.hypot(*v1); l2=math.hypot(*v2)
    if l1<40 or l2<40: return None   # limb long enough in pixels for a meaningful angle
    c=max(-1,min(1,(v1[0]*v2[0]+v1[1]*v2[1])/(l1*l2)))
    return 180-math.degrees(math.acos(c)), pts
cands=[]
for iid,anns in by.items():
    people=[a for a in anns if a['num_keypoints']>0]
    if len(people)!=1 or people[0]['iscrowd']: continue
    a=people[0]; im=imgs[iid]; x,y,w,h=a['bbox']
    if max(h/im['height'],w/im['width'])<0.6 or a['num_keypoints']<14: continue
    legs={}
    for name,(hi,ki,ai) in {'left':(11,13,15),'right':(12,14,16)}.items():
        r=flex(a['keypoints'],hi,ki,ai,im['width'],im['height'])
        if r: legs[name]={'flexion':r[0],'hip':r[1][0],'knee':r[1][1],'ankle':r[1][2]}
    if not legs: continue
    cands.append({'id':iid,'file':im['file_name'],'w':im['width'],'h':im['height'],'legs':legs,'url':im['coco_url'],'max':max(l['flexion'] for l in legs.values())})
print(len(cands),'candidates')
bins=collections.defaultdict(list)
for c in cands: bins[min(int(c['max']//25),5)].append(c)
sel=[]
for b in sorted(bins):
    random.shuffle(bins[b]); sel+=bins[b][:12]; print('bin',b*25,len(bins[b]))
os.makedirs(OUT,exist_ok=True)
for c in sel:
    p=os.path.join(OUT,f"flexion_{round(c['max'])}_coco{c['id']}.jpg"); c['fixture']=os.path.basename(p)
    if not os.path.exists(p): urllib.request.urlretrieve(c['url'],p)
json.dump(sel,open(os.path.join(OUT,'..','coco_truth.json'),'w'),indent=1); print(len(sel),'downloaded')
