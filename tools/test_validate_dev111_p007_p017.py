#!/usr/bin/env python3
"""Self-tests for DEV111 P007-P017 static validation verifier. No GUI."""
from pathlib import Path
import importlib.util,sys,unittest
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('gxtxt_p007_p017',HERE/'validate_dev111_p007_p017.py')
assert SPEC and SPEC.loader
m=importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name]=m
SPEC.loader.exec_module(m)
class CumulativePatchManifestTests(unittest.TestCase):
 def test_all_patch_versions_and_one_of_multiple_milestones(self):
  d=m.load()
  self.assertEqual(len(d['patches']),11)
  self.assertEqual([p['patch'] for p in d['patches']],[f'P{i:03d}' for i in range(7,18)])
  self.assertEqual(d['p017MilestoneStatus'],'ONE_OF_SEVERAL_MILESTONES_NOT_FINAL')
 def test_original_source_only_fixtures(self):
  d=m.load()
  self.assertEqual(len(d['selectedPortableSourceTests']),31)
  self.assertEqual(sum(x['patch']=='P017' for x in d['selectedPortableSourceTests']),29)
 def test_reject_unsafe_archive_file_paths(self):
  for p in ['/absolute','../parent','other/../../outside','D:\\private','sub\\file']:
   with self.subTest(path=p),self.assertRaises(ValueError):
    m.safe(p)
 def test_reject_invalid_native_binary(self):
  for value in [b'',b'not an elf',b'\x7fELF']:
   with self.subTest(binary=value),self.assertRaises(ValueError):
    m.elf64_x64(value)
 def test_reject_wrong_cpu_architecture(self):
  p=bytearray(8192)
  p[:6]=b'\x7fELF\x02\x01'
  p[16:18]=(3).to_bytes(2,'little')
  p[18:20]=(183).to_bytes(2,'little')
  with self.assertRaises(ValueError):m.elf64_x64(bytes(p))
 def test_all_patches_have_exact_source_hashes(self):
  d=m.load()
  for p in d['patches']:
   self.assertEqual(len(p['files']),p['originalChangedFiles']-p['excludedPrivateFiles'])
   self.assertTrue(all(len(x['publicAfter'])==64 for x in p['files']))
if __name__=='__main__':unittest.main()
