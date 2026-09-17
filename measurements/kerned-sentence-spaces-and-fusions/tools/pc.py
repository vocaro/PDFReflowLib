import sys, re
from collections import Counter
rows=[]
for l in open(sys.argv[1], encoding='utf-8'):
    f=l.rstrip('\n').split('\t')
    if f[2] not in ('adj','kern0'): continue
    left,right=f[3],f[4]
    if left not in '.,;:?!”’)' or not (right.isupper() or right in '“‘'): continue
    tc,tw=float(f[7]),float(f[8]); adj=float(f[9])
    gap=min(adj,adj+tc)
    if gap>=0.005 and f[2]=='adj': continue
    ctx=f[12]; l_,r_=ctx.split('|',1)
    lw=re.split(r'[\s]',l_)[-1]; rw=re.split(r'[\s]',r_)[0]
    rows.append((f[0],f[2],left,right,tc!=0 or tw!=0,round(gap,3),lw,rw,ctx))
c=Counter((r[1],r[4]) for r in rows); print(c)
c=Counter((r[2],r[3]) for r in rows); print(c.most_common(40))
c=Counter(r[6] for r in rows); print(len(c)); print(c.most_common(150))
with open(sys.argv[2],'w') as o:
    for r in rows: o.write('\t'.join(map(str,r))+'\n')
