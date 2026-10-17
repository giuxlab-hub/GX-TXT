# SPDX-License-Identifier: GPL-3.0-or-later
import unittest, pathlib,sys,math
from PIL import Image,ImageDraw
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'python'))
from assisted_tracing import propose, repair, insert_correction
from auto_enhancement import recommend

class AdvancedTracing(unittest.TestCase):
    def setUp(self):
        self.image=Image.new('RGB',(360,250),'white')
        d=ImageDraw.Draw(self.image)
        for x in range(30,350,50):d.line((x,15,x,240),fill='#505050',width=2)
        for y in range(30,240,40):d.line((10,y,350,y),fill='#505050',width=2)
        for x in range(10,350):
            y=int(175-94*(1-math.exp(-(x-10)/69)))
            d.point((x,y),fill='#050505');d.point((x,y+1),fill='#050505')
        self.guides=[(10,175),(55,129),(110,100),(170,88),(250,83),(340,82)]
    def test_full_preservation(self):
        p=propose(self.image,self.guides,radius=10,step=2.0)
        self.assertEqual(len(p.segments),len(self.guides)-1)
        self.assertGreater(len(p.points),150)
        self.assertEqual(p.points[0],self.guides[0]);self.assertEqual(p.points[-1],self.guides[-1])
        for i,guide in enumerate(self.guides[:-1]):self.assertEqual(p.segments[i][0],guide)
    def test_correction_preserves_other_segments(self):
        initial=propose(self.image,self.guides,radius=10,step=2)
        originals=[list(s) for s in initial.segments]
        fixed,corrected=insert_correction(initial,self.image,self.guides,1,5,(73.,112.),radius=10,step=2)
        self.assertEqual(len(fixed),len(self.guides)+1)
        self.assertEqual(corrected.segments[0],originals[0])
        self.assertEqual(corrected.segments[3:],originals[2:])
        self.assertIn((73.,112.),corrected.points)
        fixed[2]=(74.,113.)
        repaired=repair(corrected,self.image,fixed,1,radius=10,step=2)
        self.assertEqual(repaired.segments[0],corrected.segments[0])
        self.assertEqual(repaired.segments[3:],corrected.segments[3:])
        self.assertEqual(repaired.segments[1][-1],(74.,113.))
    def test_automated_enhancement_stays_non_geometric(self):
        ops,reason=recommend(self.image)
        self.assertTrue(ops)
        self.assertFalse(any(q['kind'] in ('threshold','negate','median') for q in ops))
        self.assertTrue(all(q['kind'] in ('auto_level','clahe','gamma','sharpen') for q in ops))
        self.assertIn('Heuristic',reason)

if __name__=='__main__':unittest.main()
