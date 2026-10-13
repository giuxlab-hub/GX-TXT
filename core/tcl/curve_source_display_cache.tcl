# SPDX-License-Identifier: GPL-3.0-or-later
# Curve Source owns prepared display semantics; Document owns immutable buffers.
proc ::GX::curveSourceDisplayCacheStore {document token recordId} {
    set descriptor [curveSourceDescribe $token]
    set display [curveSourceDisplay $token]
    set scene [::GX::Native2D::core scene];set writer {}
    try {
        set object [::GX::Native2D::core add $scene [dict get $display points]]
        set geometry [interactiveDocumentNative2DStore $document $scene $object [dict create role curve_source_display scientific_authority 0 disposable 1] 1]
        set receipt [dict create version 1 algorithm ordered_xy_extrema_per_source_row_bucket.v1 \
            geometry_format native2d.float64_xy_le_v1 record_id $recordId descriptor $descriptor \
            namespaces {} display [dict remove $display points]]
        foreach identity [dict get $descriptor source_identities] {
            set id [dict get $identity dataset_id]
            dict set receipt namespaces $id [datasetNamespaceGet $::GX::currentSession $id]
        }
        set bytes [encoding convertto utf-8 $receipt]
        if {[string length $bytes]>8388608} {error {Prepared display receipt exceeds its 8 MiB bound}}
        set writer [interactiveDocumentResourceOpenWriter $document [dict create format gxtxt.curve_source_display_receipt_v1 encoding utf-8 role display_cache scientific_authority 0 disposable 1 geometry $geometry]]
        interactiveDocumentResourceAppend $writer $bytes
        set resource [interactiveDocumentResourceFinalize $writer 1];set writer {}
        return [dict create version 1 record_id $recordId receipt $resource geometry $geometry]
    } finally {
        if {$writer ne {}} {interactiveDocumentResourceAbort $writer}
        ::GX::Native2D::core destroy $scene
    }
}
proc ::GX::curveSourceDisplayCacheRestore {session document cache recordId request scene} {
    if {[dict get $cache version]!=1 || [dict get $cache record_id] ne $recordId} {error {Prepared display cache version/record mismatch}}
    set reference [dict get $cache receipt]
    if {![dict exists $reference owner_generation] || [dict get $reference document_id] ne $document || [dict get $reference metadata format] ne "gxtxt.curve_source_display_receipt_v1" || [dict get $reference size_bytes]>8388608} {error {Prepared display cache owner/format mismatch}}
    set reader [interactiveDocumentResourceOpenReader $reference];set bytes {}
    try {
        while 1 {set block [interactiveDocumentResourceNext $reader];append bytes [dict get $block bytes];if {[dict get $block eof]} break}
    } finally {interactiveDocumentResourceCloseReader $reader}
    set receipt [encoding convertfrom utf-8 $bytes]
    if {[catch {dict size $receipt}] || [dict get $receipt version]!=1 || [dict get $receipt algorithm] ne "ordered_xy_extrema_per_source_row_bucket.v1" || [dict get $receipt geometry_format] ne "native2d.float64_xy_le_v1" || [dict get $receipt record_id] ne $recordId} {error {Unsupported or malformed prepared display receipt}}
    set descriptor [dict get $receipt descriptor]
    # Omitted request defaults have the same existing Curve Source semantics.
    foreach {key value} {start 0 count -1 display_budget 4096} {if {![dict exists $request $key]} {dict set request $key $value}}
    set frozen [dict get $descriptor request]
    if {[dict get $request count]==-1} {dict set request count [dict get $frozen count]}
    if {[dict size $request]!=[dict size $frozen]} {error {Prepared display binding changed}}
    dict for {key value} $request {if {![dict exists $frozen $key] || [dict get $frozen $key] ne $value} {error {Prepared display binding/reduction changed}}}
    set validation [curveSourceValidateSnapshot $session $descriptor]
    if {![dict get $validation valid]} {error "Prepared display source is [dict get $validation status]"}
    dict for {id namespace} [dict get $receipt namespaces] {if {[datasetNamespaceGet $session $id] ne $namespace} {error {Prepared display Namespace changed}}}
    set geometry [dict get $reference metadata geometry]
    if {$geometry ne [dict get $cache geometry] || [dict get $geometry document_id] ne $document} {error {Prepared display geometry owner mismatch}}
    set display [dict get $receipt display]
    set native [interactiveDocumentNative2DRestore $geometry $scene]
    try {
        set points [::GX::Native2D::core points $scene $native]
        if {[llength $points]>[dict get $descriptor display_budget] || [llength $points]!=[dict get $display display_rows] || [dict get $display source_id] ne [dict get $descriptor source_id]} {error {Prepared display count/fingerprint mismatch}}
        dict set display points $points
        if {[dict get $display breaks] ne {}} {::GX::Native2D::core set_breaks $scene $native [dict get $display breaks]}
        return [dict create native $native display $display descriptor $descriptor scientific_authority 0]
    } on error {message options} {
        ::GX::Native2D::core delete $scene $native
        return -options $options $message
    }
}
