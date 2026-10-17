# SPDX-License-Identifier: GPL-3.0-or-later
import sys, unittest
from pathlib import Path
from PIL import Image, ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from digitizer_model import Project, AxisConfig, Calibration, Series, DigitizedPoint
from quality_diagnostics import inspect

def measurement(k="m1", width=140, height=90, scale=1):
    return {"id":k,"label":k,"state":"accepted", "axes":{
        "x":{"minimum":0,"maximum":10*scale,"scale":"linear","unit":"V"},
        "y":{"minimum":0,"maximum":10*scale,"scale":"linear","unit":"mA"}},
        "calibration":{"points":{
            "bottom_left":{"pixel_x":0,"pixel_y":height-1},
            "bottom_right":{"pixel_x":width-1,"pixel_y":height-1},
            "top_left":{"pixel_x":0,"pixel_y":0},
            "top_right":{"pixel_x":width-1,"pixel_y":0}}}}

def sample(n=5):
    w,h=140,90
    p=Project();p.x_axis=AxisConfig(minimum=0,maximum=10);p.y_axis=AxisConfig(minimum=0,maximum=10)
    p.calibration=Calibration.from_dict(measurement()['calibration'])
    s=Series(id="curve-A",name="Output A")
    s.points=[DigitizedPoint(id=f'p{i}',pixel_x=10+20*i,pixel_y=50-i*2,origin='assisted' if i>1 else 'manual') for i in range(n)]
    p.series=[s]
    p.recalculate_all_points()
    im=Image.new('RGB',(w,h),'white')
    d=ImageDraw.Draw(im)
    d.line([(x.pixel_x,x.pixel_y) for x in s.points],fill=(0,0,0),width=2)
    config={'source':{'dataset_id':'raster01','sha256':'c'*64}, 'calibration_measurements':{'items':[measurement()]}}
    return config,p,im

class QualityV2(unittest.TestCase):
    def test_counts_combined_and_segments(self):
        cfg,p,im=sample()
        q=inspect(cfg,p,im.size,measurements=[measurement('m1'),measurement('m2',scale=1.1)],
                  publication_layout='combined',published_row_count=10,raster_image=im)
        self.assertEqual(q['schema_version'],'2')
        self.assertEqual(q['publication']['unique_raster_point_count'],5)
        self.assertEqual(q['publication']['published_row_count'],10)
        self.assertEqual(q['publication']['calibration_realization_count'],2)
        self.assertEqual(q['segments']['total'],4)
        self.assertEqual(len(q['curves']),1)
        self.assertEqual(q['curves'][0]['point_origins']['assisted'],3)
        self.assertEqual(len(q['calibrations']),2)
        self.assertTrue(q['image_evidence']['available'])
        self.assertIsNone(q['metrology']['accuracy'].get('value'))
        self.assertEqual(q['metrology']['accuracy']['status'],'not_assessed')
    def test_separate_and_count_guard(self):
        cfg,p,im=sample()
        q=inspect(cfg,p,im.size,measurements=[measurement()],published_row_count=5)
        self.assertFalse(q['image_evidence']['available'])
        with self.assertRaisesRegex(ValueError,'disagrees'):
            inspect(cfg,p,im.size,measurements=[measurement(),measurement('m2')],published_row_count=5)
    def test_identified_segment_warning(self):
        cfg,p,im=sample()
        p.series[0].points[-1].pixel_x=p.series[0].points[-2].pixel_x
        p.series[0].points[-1].pixel_y=p.series[0].points[-2].pixel_y
        q=inspect(cfg,p,im.size,measurements=[measurement()],published_row_count=5)
        self.assertTrue(all('curve_id' in d for d in q['segments']['records']))
        self.assertTrue(any(z['flags'] for z in q['segments']['records']))
        flagged=next(z for z in q['segments']['records'] if z['flags'])
        self.assertEqual(flagged['raster_start'][1],p.series[0].points[flagged['segment_index']].pixel_y)
    def test_axis_error_not_accuracy(self):
        cfg,p,im=sample()
        p.x_axis.minimum=p.x_axis.maximum
        q=inspect(cfg,p,im.size,measurements=[measurement()],published_row_count=5)
        self.assertEqual(q['status'],'errors')
        self.assertTrue(any(i['code']=='axis_invalid' for i in q['issues']['items']))
    def test_large_report_bound(self):
        cfg,p,im=sample(5)
        s=p.series[0]
        s.points=[DigitizedPoint(pixel_x=i*.02,pixel_y=42) for i in range(3600)]
        q=inspect(cfg,p,im.size,measurements=[measurement()],published_row_count=len(s.points))
        self.assertTrue(q['segments']['truncated'])
        self.assertLessEqual(q['segments']['returned'],1500)
        self.assertEqual(q['segments']['total'],3599)
    def test_same_image_geometry_and_no_source_mutation(self):
        cfg,p,im=sample()
        orig=[pt.to_dict() for pt in p.series[0].points]
        q=inspect(cfg,p,im.size,measurements=[measurement()],published_row_count=5,raster_image=im)
        self.assertEqual(orig,[pt.to_dict() for pt in p.series[0].points])
        self.assertEqual(q['source']['dataset_id'],'raster01')

if __name__=='__main__': unittest.main()
