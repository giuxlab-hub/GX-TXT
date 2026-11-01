# dev093 scientific transport and integration evidence

The CORE owns framing, typed arrays, buffers and lifecycle. Registered bundled
math.signal and math.numeric providers still own dispatch and call their original
Octave scientific implementations. No mathematical algorithm was copied into the
Bridge. Full response fields remain the default; uniform coordinates and explicit
result projection are additive. Scalar and small-array calls remain supported.

## Direct measured comparison

`profile-before/report.json` used accepted dev092 and `profile-after/report.json`
used integrated dev093 with identical synthetic tone, seeded-noise and add calls.
Times below are sums of those three public operations including client pack,
Bridge decode/provider/encode and client reconstruction. They are single measured
runs, not confidence intervals. The 4,096 and 65,536 cases reused the warm dev093
worker; the 8-element case includes its cold start.

| Samples | dev092 seconds | dev093 seconds |
| --- | ---: | ---: |
| 8 | 0.953849 | 0.358787 |
| 4,096 | 2.22177 | 0.065991 |
| 65,536 | 20.911566 | 0.054952 |

The warm 65,536-element triplet is approximately 380.5 times faster in this test.
Across nine calls, dev092 started nine Octave processes, sent 5,648,253 bytes of
provider request text and received 7,062,374 bytes of result text. Its instrumented
worker execution time was 22.590175 seconds, Tcl argument construction 0.097959
seconds and Tcl result parsing 0.358232 seconds. dev093 started one Octave worker,
sent 14,371 bytes of worker control JSON, and used 2,228,696 input and 3,899,840
output binary bytes. Worker decode/compute/encode were 0.020173/0.152600/0.017947
seconds. Client-side phase timings for every call are retained in the JSON.

Sampled aggregate resident memory was 275,623,936 bytes before and 140,222,464
after. These are sampled process-tree RSS measurements. The older ru_maxrss
fields inherited a parent's high-water mark and are not valid workload peaks.
The baseline worker inherited 16 numerical threads; the new worker explicitly
used one. Total observed process-tree thread maxima, including the benchmark
Python parent's numerical runtime, were 34 and 19. This is the measured deployed
policy difference, so it is not an isolated equal-thread microbenchmark.

## Scientific equivalence and contracts

The 8- and 4,096-sample arrays were bit-identical before/after. Seeded Gaussian
noise was bit-identical at all tested sizes. At 65,536 samples, the largest tone
difference was 4.3193920662432106e-12 V (combined difference
4.319378188455403e-12 V). Direct Octave JSON decoding of the old time vector
changed 3,253 dyadic coordinates by at most 1.1102230246251565e-16 seconds; the
new binary transport preserves those coordinates exactly. This observed one-ULP
legacy conversion difference explains the small phase-dependent tone difference;
there is no claim of bit-identical large tone output across legacy JSON and
binary inputs.

Real Python and Octave clients passed the retained public contracts: tiny/scalar,
large vectors, C/F matrices, multidimensional descriptors, float32 widening under
the established float64 public contract, non-finite policy, split-complex fields,
seed repeatability, explicit uniform coordinates and result projection. Negative
fixtures rejected bad shape/version/dtype/endian/order/size/count, traversal,
symlink and overflow. The older curve/polar numerical route also passed with a
16,384-point ndarray after the generic ndarray-to-Tcl compatibility correction.

A public HDF5 rank-2 append of 21,845 by 3 values preserved exact shape and value
order on physical readback. Measured begin/append/finalize times were
0.349359/0.179640/0.183427 seconds; declaration times are in
`science-phases2/report.json`. The initial phase fixture omitted a Session
manifest and correctly failed finalization; the corrected public Session fixture
passed without a product workaround.

## Full original representative workload

The complete original script01 was run once, unchanged, on an isolated new
Session: 4,194,304 samples at 65,536 Hz, sixteen 262,144-sample chunks, original
997/4,093/12,011 Hz tones, amplitudes 1/0.35/0.15 V, 0.20 V seeded Gaussian noise,
HDF5 with implicit time, and original `replace_owned=True` on first creation.
Original and executed source SHA-256 were both
`3adcb62509d6b9ef2272ae377480d9e2f3207a1eee80cb5cf254d3194009f0d7`.

The complete registered-script host lifecycle took 6.839837 seconds. The tutorial's
own generation-through-finalize interval was 3.17349 seconds, about 1.32167 million
samples/s. Forty-eight scientific calls used one Octave worker; binary input and
output were 134,218,880 and 234,881,024 bytes, control traffic 78,227 bytes.
Worker decode/compute/encode were 0.147301/0.486329/0.339731 seconds. Sampled total
peak RSS was 334,815,232 bytes, managed temporary/staging peak 38,896,800 bytes,
maximum six processes and seven threads. The actual committed Dataset ID was
recorded by the publication receipt.

Physical HDF5 readback found exactly one stored float64 signal of the correct
length, all finite, with implicit time. Full signal RMS was 0.7824810221635087 V;
recovered noise RMS was 0.19998248192643212 V. FFT peaks were exactly 997, 4,093
and 12,011 Hz. The HDF5 file was 33,563,808 bytes with SHA-256
`f814467343badce08386fab156a98e082ddc4151ca1230e22b55dcacbcd59026`.
The historical 1,318.181-second run ended in failure; it is a historical problem
reference, not a successful fresh full-size before/after comparison.

Copied downstream scripts also passed bounded checks against that Session:
step02 streamed/reduced 65,536 samples and published the summary; step03 ran the
original 65,536-point periodogram and Welch analysis, published spectrum and
rendered the registered plot; step04 used four 16,384-sample windows with two FFT
repetitions and published the policy benchmark. Their host lifecycle times were
5.122092, 13.198216 and 5.414083 seconds. Step04 selected the documented serial
fallback under its observed default-worker policy; it does not evidence a
multi-worker ProcessPool. Separate admitted job concurrency is tested below.

## Preservation and validation incidents

All full scientific runs used new private Sessions, roots and copied tutorial
scripts; no historic failed Session was reused. The official tutorial remained
unchanged throughout testing. Its optional output adapter changes only the
selected output ID and replace flag; the bounded bound-input test additionally
changes sample count and seed from a synthetic input in its disposable copy.

An initial baseline profiler import generated 33 new Python bytecode files inside
the accepted expanded tree. Only those newly generated files absent from the
recorded baseline were removed. Every retained file hash and the complete file
inventory then matched the original baseline exactly; the correction receipt is
`baseline-profile-bytecode-correction.json`. All subsequent baseline imports use
`-B` and `PYTHONDONTWRITEBYTECODE`. One early bounded profile used default Resource
Manager accounting because its resource-root environment was missing; its owned
buffer was normally released/cleaned, leaving an accounting record only. The
runner was corrected to isolate both resource inventory and storage. Full and
concurrent scientific campaigns isolated those roots from the outset.

## Supervised bound-input and bound-output concurrency

`science-concurrent-final/report.json` has status PASS. One 262,144-sample job
ran with max_jobs=1, followed by two jobs with max_jobs=2, each reserving 512 MiB
and one internal numerical thread. Each job read its actual bound synthetic input
through Canonical Dataset API and used the optional tutorial output adapter.
Input A retained seed 20261006; input B selected 20261007. All three completed via
public `scriptJobSubmit`. Scientific input payload hashes remained unchanged.

The single job took 5.149725 seconds. The concurrent pair occupied 8.307540
seconds with 3.882245 seconds of actual execution overlap; each had an independent
Octave worker. This is evidence of admitted overlap and correct resources, not a
claim of ideal scaling: per-call input revision checks and short-run setup/commit
costs are included. Each worker made three scientific calls. Per-job peak RSS was
279,891,968, 298,270,720 and 316,436,480 bytes; each peaked at six processes and
seven total threads including the guardian/Bridge/helpers. The internal Octave
thread budget was one. The generic latest CPU snapshot is retained in job records
but is not presented as accumulated total CPU time.

The serial and concurrent input-A HDF5 files were byte-identical, SHA-256
`c2213e461e5df7dcf27adc7241c64b792dfeb85a1fb32220289b7ef548ae0bfe`.
Input B produced a distinct file with SHA-256
`5932af95c33dba9aa166ef7f330531e529d9a0010e5b4b140cd16bf3a8e4651d`.
Each contained exactly 262,144 finite float64 signal values and all three expected
tone frequencies. Noise RMS was 0.1992669408622537 V for input A and
0.20045770064949955 V for B. Actual receipts named science_serial,
science_concurrent_a and science_concurrent_b, matching requested output bindings.
All nine managed job/Bridge/scientific temporary allocations were removed on
normal completion. Scientific outputs, diagnostic logs and the publication
recovery authority remained protected. Two externally observed, already-absent
CSV staging observations remained accounting records, not physical residue.

The first concurrency prerequisite exposed a real false-stale-input issue:
Canonical read_range inferred schema version 3 in memory, changing a token built
from a version-2 loaded registry projection. The publication authority was
corrected to fingerprint committed records and preserve a truthful committed
baseline. The independent publication regression proved repeated reads stable
and actual metadata/schema edits invalidating; the complete bound-input
scientific campaign then passed. The first campaign failed before publication.

The final jobs completed successfully on their first run. Their initial verifier
file was unfortunately named concurrent.py, shadowing Python's concurrent module
when numpy.testing imported it. The runner was renamed scientific_jobs.py and
its read-only --verify-existing path completed all scientific and resource checks
against the already completed outputs. Numerical jobs were not rerun. Aggregate
outer-driver sampled peaks were lost by that verifier failure and are explicitly
null; durable supervisor per-job peaks above are available and authoritative.
