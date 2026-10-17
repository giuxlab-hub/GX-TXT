"""Exact total counts, deterministic arclength quotas, guide points preserved."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'python'))
import pytest
from assisted_sampling import sample_proposal_segments, sample_segment


def test_guaranteed_total_and_anchors():
    samples=[[(0,0),(10,3),(20,0)],[(20,0),(21,20),(40,20)],[(40,20),(65,25)]]
    for count in (4,5,8,15,50,200,900):
        a=sample_proposal_segments(samples,count)
        assert sum(map(len,a))-len(a)+1==count
        assert a[0][0]==(0,0)
        assert a[0][-1]==a[1][0]==(20,0)
        assert a[1][-1]==a[2][0]==(40,20)
        assert a[2][-1]==(65,25)
        assert a==sample_proposal_segments(samples,count)


def test_reject_impossible_density():
    spans=[[(0,0),(5,1)],[(5,1),(20,9)]]
    with pytest.raises(ValueError,match='Output points'):sample_proposal_segments(spans,2)
    with pytest.raises(ValueError,match='Output points'):sample_proposal_segments(spans,10001)
    assert sample_segment([(0,0),(0,0),(10,10)],2)==[(0,0),(10,10)]
