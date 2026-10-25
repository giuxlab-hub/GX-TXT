#!/usr/bin/env python3
"""Unit tests for read-only DEV111-P019 source/package verification."""
import importlib.util,pathlib,sys,unittest
HERE=pathlib.Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('gxtxt_dev111_p019',HERE/'validate_dev111_p019.py')
assert spec and spec.loader
m=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=m
spec.loader.exec_module(m)
class P019SourceUnitTests(unittest.TestCase):
 def test_original_test_and_source_count(self):
  d=m.inventory()
  self.assertEqual(len(d['originalSourceOnlyFixtures']),29)
  self.assertEqual(len(d['files']),28)
  self.assertEqual(d['excludedInternalFiles'],397)
 def test_patch_predecessor(self):
  d=m.inventory()
  self.assertEqual(d['priorP018Commit'],m.P018)
  self.assertEqual(d['newP019Commit'],m.EXPECTED)
  self.assertEqual(d['predecessorPatch'],18)
 def test_only_two_nonfunctional_normalizations(self):
  d=m.inventory()
  self.assertEqual(len(d['normalizationPaths']),2)
  self.assertEqual(sum(not x['sourceExact'] for x in d['files']),2)
 def test_invalid_relative_paths_rejected(self):
  for x in ('../private','/absolute','C:\\secret','folder\\target'):
   with self.subTest(path=x),self.assertRaises(ValueError):m.relpath(x)
 def test_original_sources_have_unique_paths(self):
  d=m.inventory()
  self.assertEqual(len(set(x['path'] for x in d['originalSourceOnlyFixtures'])),29)
if __name__=='__main__':unittest.main()
