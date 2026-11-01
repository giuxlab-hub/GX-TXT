# Scientific measurement importer

This independently authored Acquisition module uses the existing CORE source,
typed output and publication services. Its profiles are not Library ingestion
commands. This candidate requires the matching P033 CORE; the framework version
number alone does not establish that additive SDK/schema compatibility.

## Supported source profiles and limits

- **Explicit spectral CSV**: UTF-8 columns selected by saved configuration. Declare
  actual spectrum kind, X/Y quantities, representation and units. A wavelength
  label does not establish nm. Delimiter/header/column selections use the shared
  CORE parser. No unit, normalization or scientific modality is guessed.
- **JCAMP-DX**: the shared CORE decoder supports its declared AFFN/explicit-pair
  subset and retains original headers. Uniform X uses the source FIRSTX/LASTX
  count rule; explicit pairs retain their order. Unsupported variants refuse.
- **Andor SIF**: qualified LF65567, single-ROI primary float32 layout. Detector
  pixel coordinates are the default. The literal source labels Counts and
  Counts (Bg corrected per second) retain different count/count/s semantics;
  no background correction or rate conversion is applied. Physical cubic X needs
  explicitly reviewed source quantity/unit and finite source coefficients;
  offset/binned physical calibration is not qualified. The raw coefficient strings
  remain visible. Images/stacks preserve X/Y/frame dimensions and source pixel
  order; their current shape tests are synthetic, not authentic-camera-image
  acceptance. Raw timestamps/ticks retain their integer values without an invented
  time unit. Multiple ROIs and other layouts refuse instead of flattening.
- **PerkinElmer SP**: PEPE signature, one constant-interval dataset, original
  float64 signal, qualified UV/IR data tags, explicit absorbance A/enum1 and known
  wavenumber/wavelength label/enums. Source start/step/count must agree with end.
  X order and all Y values remain original; there is no sorting, resampling or
  fluorescence-only interpretation. Opaque history/annotations stay in the
  original source and are not reapplied. Vendor checksum/history semantics are
  not claimed decoded. Unknown units, typed variants or invalid-region records
  refuse. Authentic evidence currently covers one public IR spectrum; a complete
  independent source-paired numerical/canonical gate remains open.

- **PerkinElmer PRF, limited structural profile**: a distinct MS-CFBv3 container,
  never interpreted as SP. The direct intensity-profile storage must have the
  declared CLSID, CONTENTS count and exact explicit float64 prop36/prop37 arrays.
  FAT, DIFAT, directory, MiniFAT and root mini-stream bounds/ownership are checked.
  No COM activation or external reader is used. CFBv4, ambiguous storages, invalid
  chains, aliased/truncated arrays and nonfinite samples refuse. Coordinates and
  signal bytes retain original order without sorting/resampling. This profile is
  **SYNTHETIC-CONTAINER QUALIFIED; REAL PRF COMPATIBILITY UNVERIFIED**: an authentic
  permitted binary/reference pair has not yet been obtained.

PRF inspection may report unknown units. Before Test/import, explicitly review
`prf_time_unit` (s/min/h), `prf_signal_unit` and `prf_signal_quantity` against actual
source evidence. These are declarations, not numeric conversions. Numeric time
is a coordinate with role time in timeseries.table, not HMS elapsed_time or an
invented absolute timestamp. A reference converter's seconds/RMS labels alone
do not establish authentic source units. Synthetic tests do not establish them.

The genuine fluorescence reference and full independent universal module
acceptance remain unfinished. The linked Fluorophores substance records617/866/
340 returned HTTP500 at the bounded current intake; its accessible catalogue and
disclaimer are not CSV measurements. The officially linked Spectragryph sample
ZIP redirected to HTML. No download endpoint, paired spectrum, layout or units
are invented from those unavailable sources. No full-format vendor compatibility
is claimed from an extension or a synthetic fixture.

## JCAMP source metadata and saved declarations (1.0.1)

JCAMP scientific metadata comes from the shared CORE parser's observed headers.
The six scientific declaration fields are required for CSV; for JCAMP, blank
fields retain the source metadata and nonempty fields must match it exactly.
A declaration left over from CSV (for example nm against MICROMETERS → um) is
refused before import. No numerical conversion, unit alias substitution or
relabelling is performed. Clear conflicting declarations when changing profiles.
JCAMP files with ambiguous DATA TYPE or unsupported source units are explicitly
unsupported in this qualified profile; entering a new label cannot make them
scientifically valid. The source RAW and existing Datasets remain unchanged on
refusal. This check does not alter the CORE parser or source numeric values.

## Normal review and import

Create or open the intended real Session, then select this module on Acquisition.
The primary top-row Acquisition menu offers Importer options, Importer Builder,
Contracts, Refresh importers and current importer Help/About. File-profile options
start collapsed; show them to choose the actual saved format profile and review
its declarations, then hide them with the same menu. Source/configuration values
are retained. Legacy instrument configuration keeps its normal visible default.

Add file / Add files places original sources in Pending imports. Review Preview
and Variables before Import. A profile with one declared output contract receives
that proposal automatically; SIF can produce a true1D spectrum or an actual
multidimensional measurement, so its ambiguous proposal is initially empty.
Inspect the source shape/semantics and explicitly review the proposal. The source
and producer determine actual published contracts: selecting a contract does not
convert units, flatten an image or force a scientifically different output.
The actual imported contract remains inspectable in Dataset Metadata. Original
RAW policy Copy/Reference retains the same source identity and ownership guards.
Keep the source-declared units, roles and dimensions. Variable IDs/display labels
may be reviewed consistently, but this module does not silently apply physical
scale/offset, dtype, role or reshape conversions. Reinspect after a source/config
change. All coordinates required by the output must remain present.

Import alone may publish through the normal Acquisition/RAW/Group owners. In the
Acquisition Plugin Builder, Run → Test uses the current source/build/config and
**discards** typed outputs; Test is not an install, Session, publication or a
substitute for scientific acceptance. Validate and Build check source/AST/capability
admission and compile a real module, not the physical validity of every format.
Retain failed-source diagnostics rather than changing labels to force admission.

The output contract follows actual data: spectral X/Y uses spectrum.scientific;
SIF images/stacks use measurement.numeric_array with a separately installed
contract.scientific_measurement provider. Preview selection is contract-driven
and optional, independent of importer identity/version. Source and Metadata remain
available when a compatible graphical Preview is absent.

PRF container implementation references Microsoft's published MS-CFB structures:
https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/05060311-bfce-4b12-874d-71fd4ce63aea
https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/60fe8611-66c3-496b-b70d-a504c94c9ace
The original module implementation uses only inert identifiers/offset facts from
the separately inspected PerkinElmer2CSV PRF reference; no unlicensed reference
source or dependency is included. No sample rights are inferred from file format
documentation or from the unrelated SP repository licence.

## Source and third-party notices

Original parser header labels can contain punctuation that is not a valid flat
Dataset Metadata key; their values can contain multiline copyright notices.
The module preserves the complete parsed text map using the declared reversible
encoding `measurement.source_metadata_key_encoding=utf8_hex_v1` and
`measurement.source_metadata_value_encoding=utf8_hex_v1`. For each original parsed
key, token `k_` plus lowercase hexadecimal UTF-8 bytes identifies both fields:
`measurement.source_metadata.<token>` holds the hexadecimal UTF-8 value, and
`measurement.source_metadata_key.<token>` holds the exact original parsed label.
All keys/values use the encoding, including already-valid or encoded-looking
labels, so slash/underscore/space labels cannot collide. For example parsed key
`jcamp.a/b` has token `k_6a63616d702e612f62`; value A, newline, B is `410a42`.
Standard hexadecimal decoding followed by UTF-8 decoding recovers the exact
strings, including multiline, Unicode and empty values. No header is dropped or
lossily renamed. RAW retains the original file bytes/encoding. Invalid line-break
or NUL labels and projections beyond48KiB refuse without truncation. This is
inert source metadata, not a permission, command or alternate scientific store.

The authored module is GPL-3.0-or-later; the distribution contains the GPL license.
All authored sources are bundled for normal editable Project import. Binary use
also retains the following compatible third-party notices in this manual and
bundled source. No third-party Python/JavaScript/.NET reader is required at runtime.

SIF format reference/adaptation: fujiisoup/sif_parser, _sif_open.py, commit
8362a4844d7521c8cbd889ff80694332281ed1d8. Its source notes the earlier Marcel
Leutenegger MATLAB work. The pinned upstream LICENSE has no copyright-holder/year
line; no attribution is invented. Source and full notice:
https://github.com/fujiisoup/sif_parser/tree/8362a4844d7521c8cbd889ff80694332281ed1d8

# 3-Clause BSD License
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

SP format reference/adaptation: cheminfo/spc-parser, src/perkinElmer, pinned Git
tree89040729ebdfae52bb279e505f6574a7decc2ea1. The public test fixture and source
references have their own provenance record; laboratory/model/permission facts
are not invented from the reader's name. No source from the unlicensed
PerkinElmer2CSV repository is repackaged.
https://github.com/cheminfo/spc-parser/tree/main/src/perkinElmer

MIT License

Copyright (c) 2021 cheminfo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
