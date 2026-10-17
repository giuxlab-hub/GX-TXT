"""Regression for partial acceptance density: consistent N, no duplicates."""
import sys,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from assisted_sampling import sample_proposal_segments

spans=[[(0.,10.),(5.,8.),(13.,4.)],[(13.,4.),(28.,6.),(44.,14.)],[(44.,14.),(80.,35.)]]
for n in (4,10,40,80):
 sampled=sample_proposal_segments(spans,n)
 # Simulate 3, then 1, then 2: the original viewer's deduplication policy
 accepted={};committed=set()
 for i in (2,0,1):
  segment=sampled[i]
  start=1 if (i-1 in committed) else 0
  end=len(segment)-1 if (i+1 in committed) else len(segment)
  accepted[i]=segment[start:end]
  committed.add(i)
 # User acceptance order must NOT create duplicates at shared guide vertices.
 flat=sum((accepted[i] for i in (0,1,2)),[])
 assert len(flat)==n,(n,len(flat))
 assert len(set(flat))==len(flat)
print('PASS partial interval quotas and deduplicated guides')
