# SPDX-License-Identifier: GPL-3.0-or-later
import pathlib,sys,unittest
from PIL import Image,ImageDraw
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'python'))
from assisted_tracing import propose
from digitizer_model import DigitizedPoint
from quality_diagnostics import inspect
from digitizer_model import Project,AxisConfig,Calibration,Series

class AssistedTests(unittest.TestCase):
    def setUp(self):
        self.img=Image.new('RGB',(240,130),'white');d=ImageDraw.Draw(self.img)
        d.line([(10,70),(70,45),(130,80),(190,30),(230,40)],fill='black',width=4)
    def test_guides_and_anchor_preservation(self):
        g=[(10,70),(70,45),(130,80),(190,30),(230,40)]
        x=propose(self.img,g,radius=12,step=3)
        self.assertGreater(len(x.points),70)
        self.assertEqual(x.points[0],g[0]);self.assertEqual(x.points[-1],g[-1])
        for gx,gy in g:
            self.assertTrue(any(abs(x-gx)<.01 and abs(y-gy)<.01 for x,y in x.points))
    def test_nonmonotone_and_vertical(self):
        g=[(30,10),(36,65),(30,118),(80,110),(80,20)]
        x=propose(self.img,g,radius=8,step=2)
        self.assertEqual(x.segment_count,4)
    def test_reject_duplicate_guides(self):
        with self.assertRaises(ValueError):propose(self.img,[(5,5),(5,5)])
    def test_point_origin_roundtrip(self):
        p=DigitizedPoint(origin='assisted',pixel_x=10,pixel_y=11)
        self.assertEqual(DigitizedPoint.from_dict(p.to_dict()).origin,'assisted')
        self.assertEqual(DigitizedPoint.from_dict({'pixel':{'x':1,'y':2}}).origin,'manual')
    def test_quality_honest_and_bad_axes(self):
        p=Project()
        p.x_axis=AxisConfig(minimum=2,maximum=2)
        p.y_axis=AxisConfig(minimum=0,maximum=100)
        s=Series(name='trace');s.points=[DigitizedPoint(origin='assisted',pixel_x=1,pixel_y=2)]
        p.series=[s]
        spec={'id':'m1','label':'Calibration 1','state':'accepted',
              'axes':{'x':{'minimum':0,'maximum':10,'scale':'linear','unit':'V'},
                      'y':{'minimum':0,'maximum':10,'scale':'linear','unit':'mA'}},
              'calibration':{'points':{'bottom_left':{'pixel_x':0,'pixel_y':129},
                  'bottom_right':{'pixel_x':239,'pixel_y':129},
                  'top_left':{'pixel_x':0,'pixel_y':0},
                  'top_right':{'pixel_x':239,'pixel_y':0}}}}
        report=inspect({},p,(240,130),measurements=[spec],published_row_count=1)
        self.assertEqual(report['point_origins']['assisted'],1)
        self.assertEqual(report['metrology']['accuracy']['status'],'not_assessed')
        self.assertEqual(report['metrology']['uncertainty']['status'],'not_assessed')
        self.assertTrue(any(item['code']=='axis_invalid' for item in report['issues']['items']))

if __name__=='__main__':unittest.main()
