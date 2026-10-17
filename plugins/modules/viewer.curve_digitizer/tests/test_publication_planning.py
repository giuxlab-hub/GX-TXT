# SPDX-License-Identifier: GPL-3.0-or-later
import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from publication_planning import plan_datasets, validate_template

class PublicationNamingTest(unittest.TestCase):
    def setUp(self):
        self.items = [{'id':'m1', 'label':'Calibration A', 'state':'accepted'},
                      {'id':'m2', 'label':'Calibration B', 'state':'accepted'},
                      {'id':'m3', 'label':'Draft', 'state':'draft'}]
    def test_separate(self):
        p = plan_datasets(self.items,['m1','m2'],layout='separate',name='sample',
                         template='[name].[calibration].curves',configuration='cfg')
        self.assertEqual([s['dataset_id'] for s in p], ['sample.calibration_a.curves','sample.calibration_b.curves'])
    def test_combined(self):
        p = plan_datasets(self.items,['m1','m2'],layout='combined',name='sample',
                         template='[name].[calibration].curves',configuration='cfg')
        self.assertEqual(p[0]['dataset_id'],'sample.combined.curves')
        self.assertEqual(p[0]['measurement_ids'],['m1','m2'])
    def test_collision(self):
        items=[dict(x) for x in self.items]
        items[1]['label']='Calibration A'
        with self.assertRaisesRegex(ValueError,'collision'):
            plan_datasets(items,['m1','m2'],layout='separate',name='sample',
                          template='[name].[calibration]',configuration='cfg')
    def test_draft(self):
        with self.assertRaisesRegex(ValueError,'accepted'):
            plan_datasets(self.items,['m1','m3'],layout='combined',name='sample',
                          template='[name].[calibration]',configuration='cfg')
    def test_bad_template(self):
        with self.assertRaises(ValueError): validate_template('[name].[thing]')
        with self.assertRaises(ValueError): validate_template('../[name]')
    def test_stable_index(self):
        p=plan_datasets(self.items,['m1','m2'],layout='separate',name='Data',
                  template='[name].[index].[calibration_id]',configuration='cfg')
        self.assertEqual([x['dataset_id'] for x in p],['Data.1.m1','Data.2.m2'])
if __name__ == '__main__': unittest.main()
