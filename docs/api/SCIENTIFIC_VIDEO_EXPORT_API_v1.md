# Scientific Video Export API v1

Development source under TASK210 MAIN344. The two trusted CORE host/module routes
below were independently approved for bounded implementation. Central loader,
matching precompiled native capture support and focused actual qualification are
not adopted by this source packet. No render, encode, GUI or scientific PASS is
implied. Ordinary Scripts, Bridge and authored native Viewer code receive no new
filesystem, process, encoder or scientific operation grant.

`::GX::native3DAnimationDescribe moduleId providerId timelineId` returns the
existing source owner's bounded inert `description`: logical module/provider/
timeline, original sample count/times/unit, declared tracks/source identities,
render settings and qualified availability. It does not render, hash/copy large
dependencies, probe an encoder or issue an executable handle. Missing units or
producer metadata remain unknown. Capability declarations and advertised encoder
flags are distinct from actual current runtime acceptance.

`::GX::native3DAnimationExportAsync moduleId providerId timelineId destination options callback`
captures the current unsaved host scene through the same source owner and returns
an existing ScriptJob auxiliary request ID. The callback is a trusted Tcl list
prefix and receives one terminal dictionary. Use existing
`::GX::scriptJobRequestCancel requestId` for cancellation. This is an asynchronous
host operation, not a new durable Job service or export registry. Callback clients
must guard their own window/project incarnation; Session/source identity is also
checked by the adapter before commit authorization.
The returned request ID controls the original rendering/encoding/publication
process until its transport closes. If an interrupted commit needs a subsequent
read-only destination check, that separate managed check may continue for up
to120 seconds; cancelling the already closed original request does not cancel
it. An already running check uses the existing root UI lifetime owner. The
adapter refuses to spawn a new check after its captured root has closed or
changed; the outcome then remains explicitly unknown.
Closing an export dialog may leave this bounded read-only confirmation running;
it never retries or mutates the destination. This limitation is explicit rather
than claiming one request ID controls two different managed processes.

| Option | Initial contract |
| --- | --- |
| first_index / last_index | Inclusive original sample indices; defaults0 and last; at most256 original samples. |
| width / height | Even16..4096; defaults1280x720. |
| fps | Two positive integers numerator/denominator, each<=1000000; rate<=120. Default24/1 when duration is absent. |
| playback_duration_seconds | Alternative to fps, positive finite<=86400. Rounded to a microsecond playback grid; resulting rate must be<=120. |
| quality | draft/normal/high map to libx264 CRF28/23/18, fixed medium preset. |
| policy | create_only. Existing destinations, including dangling links, are refused. |

Unknown options fail. Resulting N/FPS duration is at most86400 seconds. One encoded
frame corresponds to each selected original sample, with no interpolation.
Original scientific times may be nonuniform. Frame ordinal k has videoPTS k/FPS;
its scientific time is the exact original sample first_index+k, with the original
declared unit. An MP4 is a presentation derivative and never replaces/registers
canonical scientific arrays or a new animation Dataset contract.

The first slice supports base Viewer scenes with actual renderer-compatible CSV Dataset sources and
accepted self-contained scientific artifacts under the Native3D source owner.
Unsupported formats, sparse/unavailable selected sources, external attributes/
textures not captured through an admitted owner and unsupported captions fail
explicitly. A copied HDF5 file is not relabelled CSV. The complete captured source
budget is256MiB. Existing per-frame PNG size bounds,2GiB encoded video and4MiB
manifest bounds apply, with conservative Resource expected-byte admission. These
are not measured RSS or performance guarantees. Existing native process limits
are applied to the renderer; missing safe process/group policy refuses launch.
Admission includes the initialization PNG, all selected PNGs, source copies,
staged video and a working-file allowance; retained diagnostics are admitted
separately. The fresh renderer keeps its existing disk caches disabled for this
one derivative. This is not an aggregate filesystem quota or full-memory proof.

The worker restores an inert snapshot only in its own process, copies/verifies
the complete admitted source dependency set, and renders through the existing
native renderer in a separate process. It never seeks or saves the live Viewer.
Original Dataset metadata/registry revisions and source files are rechecked
before and after encoding/authorization. The initial camera policy requires the
same captured camera across samples; source/time semantics never come from camera
motion. Actual native frame/time/unit, source/time captions, PNG SHA, render
settings, renderer/encoder identity and separate videoPTS are retained in the
manifest. Its inert source receipt also retains the actual verified canonical
Dataset SHA-256 and byte count, stable variable/schema mapping used for rendering,
and corresponding logical registered metadata/artifact dependency identities.
These come from the existing capture verification, including valid layers whose
optional source hash fields are empty. Private worker-copy paths and ephemeral
Session revision tokens are not provenance identities. The existing4MiB manifest
bound still applies; exceeding it fails before publication.
An active matching Engine3D ScientificDocument presentation is explicitly refused:
its canonical axes, colorbar and other figure data are injected outside the base
Viewer scene and are not captured by this slice. Stale document markers also
refuse. The parent binds its private captured host presentation generation and
mount lifetime, so an open/rebind or base-to-document-to-base transition during
capture invalidates authorization. No GUI generation is published as provenance
or reconstructed in the headless worker. Document-backed export remains unfinished.
Native figure text actually supplied by an admitted base scene is preserved
within the caption bounds. Generic caption coordinates are hidden render coordinates from real
nondegenerate bounds, with no physical calibration claim.
The initial caption adapter admits strict BMP UTF-8 text and refuses controls,
modified UTF-8/surrogates and non-BMP text rather than corrupting source labels
or unit meaning. Export additionally requires single-line title/legend text:
literal LF/CR is explicitly unsupported by the existing private renderer line
protocol and is refused rather than truncated or normalized. This export limit
does not alter interactive figure support. Existing native title/legend text is
preserved within those explicit bounds; actual glyph/readability qualification
remains separate.

Configured preinstalled FFmpeg/FFprobe are resolved through Runtime Tools. The
worker validates the advertised libx264/yuv420p surface and then actually encodes
and probes the result. Fixed argv and owned local PNG patterns are used; there is
no shell, microphone, desktop recorder, solver, upload or runtime compiler. Actual
FFprobe H.264/MP4, dimensions, frame count, rational FPS and N/FPS duration must
match before authorization. The whole operation has a one-hour managed timeout;
MAIN supplies narrower actual validation allocations separately.

Destination must be an absolute `.mp4` in an existing external directory, outside
the current scientific Session, framework and managed Resource storage. Existing
FilePublication Copy performs complete-file create-only publication. Only the
MP4 is published externally in this slice. Provenance is an inert
`manifest.tcldict` under an existing retained-diagnostic Resource, with its real
configured retention period. It is not a new canonical store or an indefinite
export-history guarantee. Public receipts expose the Resource ID and manifest
SHA, not worker paths, native pointers or callable commands.

The worker emits at most8 bounded controls total and waits for acknowledgement
of its terminal receipt before exiting. Detailed per-frame data stays in the
owned manifest. Generic transport EOF/cancellation cannot replace an observed
publication receipt with a false 'no file' result.

Terminal statuses are `published`, `failed`, `cancelled`,
`finalization_outcome_unknown`, `published_reconciled`, `absent_reconciled` and
`conflict_reconciled`. `published` includes destination, exact video SHA/bytes,
actual publication receipt, manifest SHA, original sample-order timing and source
IDs. `published_reconciled` instead proves the matching authorized encoded bytes
are present, with the previously captured manifest SHA/timing; it explicitly
reports `publication_receipt_status unavailable_after_interruption` and does not
invent the missing original publication receipt. Resource release information describes only actual owner calls;
it is not an all-descendant or full-cleanup certificate.

Cancellation or root shutdown after commit authorization can interrupt existing
publication. A missing terminal outcome therefore triggers a fixed read-only
background reconciliation against the exact authorized destination SHA/size.
Matching bytes are reported as reconciled; absence and conflicts remain explicit.
An interrupted/unavailable reconciliation remains `finalization_outcome_unknown`.
The adapter never deletes a committed video, retries publication, overwrites a
conflict or sweeps unknown temporary files. Diagnostic retention uses the
existing Resource policy. Read-only reconciliation has its own120-second managed
timeout and does not render, encode, call scientific providers or mutate sources.

Actual source-qualified GUI export and independently inspected playable MP4,
FFprobe and start/middle/end content/labels remain required evidence. Source
review alone does not establish those results.
