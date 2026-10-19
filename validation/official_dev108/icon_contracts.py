"""Bounded resource admission, not scientific or complete GUI acceptance."""
from pathlib import Path
import sys,tempfile,json,base64,copy
W=Path(__file__).resolve().parents[2];C=W/'_work_gxtxt_dev108'
sys.path.insert(0,str(C/'core/python'))
import gxtxt_viewer_icons as icons
out=W/'_private_dev108/icon-contracts';out.mkdir(exist_ok=False)
cases=[]
def check(name,expected,fn):
    try:fn();observed=True;error=''
    except Exception as e:observed=False;error=str(e)
    cases.append(dict(id=name,status='PASS' if observed==expected else 'FAIL',accepted=observed,error=error))
safe=C/'core/assets/icons/play.svg'
asset=icons.admit(str(safe),'Play','Controls','GPL-3.0-or-later')
check('safe-svg',True,lambda:icons.validate({k:str(int(v)) if isinstance(v,bool) else str(v) for k,v in asset.items()}))
png=out/'play.png';png.write_bytes(base64.b64decode(asset['png']))
check('safe-png',True,lambda:icons.admit(str(png),'Play','Controls','GPL-3.0-or-later'))
bad=copy.deepcopy(asset);bad['sha256']='0'*64
check('hash-tamper',False,lambda:icons.validate(bad))
for name,payload in {'script':'<svg width="32" height="32"><script>alert(1)</script></svg>',
 'external':'<svg width="32" height="32"><image href="file:///etc/passwd"/></svg>',
 'entity':'<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg width="32" height="32"/>',
 'css':'<svg width="32" height="32"><path style="fill:url(http://example.invalid)"/></svg>',
 'dimensions':'<svg width="999" height="32"/>','oversize':' '*262145}.items():
    p=out/(name+'.svg');p.write_text(payload)
    check(name,False,lambda p=p:icons.admit(str(p),'Invalid','Controls','GPL-3.0-or-later'))
link=out/'link.svg';link.symlink_to(safe)
check('symlink',False,lambda:icons.admit(str(link),'Invalid','Controls','GPL-3.0-or-later'))
(out/'report.json').write_text(json.dumps(cases,indent=2)+'\n')
print(json.dumps(cases,indent=2));assert all(c['status']=='PASS' for c in cases)
