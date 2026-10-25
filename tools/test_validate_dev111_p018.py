#!/usr/bin/env python3
"""Unit tests for the independently verifiable DEV111-P018 source chain."""
import importlib.util,pathlib,sys,unittest
HERE=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('gxtxt_p018',HERE/'validate_dev111_p018.py')
assert spec and spec.loader
m=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=m
spec.loader.exec_module(m)
class PublicP018SourceUnitTests(unittest.TestCase):
 def test_typed_original_author_source_files(self):
  d=m.inventory()
  self.assertEqual(len(d['files']),26)
  self.assertEqual(len(d['originalSourceOnlyFixtures']),13)
  self.assertEqual(d['excludedInternalFiles'],202)
 def test_exact_predecessor_and_version(self):
  d=m.inventory()
  self.assertEqual(d['priorP017Commit'],m.P017)
  self.assertEqual(d['newP018Commit'],m.EXPECTED)
  self.assertEqual(d['predecessorPatch'],17)
 def test_only_three_nonfunctional_source_changes(self):
  d=m.inventory()
  self.assertEqual(len(d['normalizationPaths']),3)
  self.assertEqual(sum(not p['sourceExact'] for p in d['files']),3)
 def test_reject_path_escape(self):
  for p in ('../escape','/root','C:\\secret','dir\\other'):
   with self.subTest(path=p):
    with self.assertRaises(ValueError):m.relpath(p)
 def test_original_fixtures_have_distinct_sha(self):
  d=m.inventory()
  self.assertEqual(len(set(x['path'] for x in d['originalSourceOnlyFixtures'])),13)
if __name__=='__main__':unittest.main()
