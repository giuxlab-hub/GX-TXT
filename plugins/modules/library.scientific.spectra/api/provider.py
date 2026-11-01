# SPDX-License-Identifier: GPL-3.0-or-later
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[4]/'core/python'))
from scientific_library_records import *
LIBRARY_TYPE='scientific.spectra'
TYPED_RECORDS=True
LIBRARY_CAPABILITIES=CAPABILITIES
