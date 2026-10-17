# Digitizer calibration capture and publication lineage; CORE owns interpretation.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::CurveDigitizerCompanion {variable uncertaintyReviews {}}
proc ::GX::CurveDigitizerCompanion::uncertaintyReview {document expectedSha} {
    variable moduleRoot;variable uncertaintyReviews
    set full [_ownedDocumentRead $document]
    if {[dict get $full sha256] ne $expectedSha} {error {Configuration changed; save and review the current calibration and points}}
    set source [sourceResolve $document]
    set key [list [sessionToken] $document $expectedSha]
    if {[dict exists $uncertaintyReviews $key]} {
        set review [dict get $uncertaintyReviews $key]
        dict for {role reference} [dict get $review resources] {::GX::interactiveDocumentResourceInfo $reference}
        return $review
    }
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set allocation [::GX::resourceManagementAllocate scientific_transport [dict create kind directory session $::GX::currentSession lifetime computation]]
    set workspace [dict get $allocation path]
    try {
        set path [file join $workspace configuration.json]
        set channel [open $path {WRONLY CREAT EXCL}]
        try {fconfigure $channel -encoding utf-8 -translation lf;puts -nonewline $channel [dict get $full payload]} finally {close $channel}
        if {[::GX::sha256File $path] ne $expectedSha} {error {Configuration encoding differs from its saved identity}}
        exec [_pythonExecutable] [file join $moduleRoot python uncertainty_request.py] $path $workspace 2>@1
        set root [file normalize [file join $moduleRoot .. .. ..]]
        exec [::GX::runtimeToolRequired octave] --quiet --no-gui [file join $root core octave gxtxt_scientific_provider_worker_v1.m] gxtxt_digitizer_uncertainty_v1 $moduleRoot [file join $workspace request.json] [file join $workspace response.ini] 2>@1
        set raw [dict get [::GX::ScientificTransportv1::readResult [file join $workspace response.ini]] values summary]
        set context [_runBridgeContext [dict get $full payload]]
        set context [dict create source_document_id $document source_document_sha256 $expectedSha source_dataset_id [dict get $context source_dataset_id] source_sha256 [dict get $context source_sha256] row_identity original_point_ids point_ids_sha256 [::GX::sha256File [file join $workspace points.tsv]]]
        set meaning [::GX::StatisticsV1::digitizationInterpretation $raw $context]
        set resources {}
        foreach {role file format} {configuration configuration.json gxtxt.curve_digitizer.configuration points points.tsv gxtxt.digitizer_point_order.v1 state state.mat gxtxt.digitization_uncertainty.mat.v1 values values.bin float64_column_major_le} {
            dict set resources $role [::GX::interactiveDocumentResourceImportNumeric $document [file join $workspace $file] [dict create format $format role digitization_$role point_count [dict get $raw point_count]]]
        }
        set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict create format gxtxt.digitization_interpretation.tcldict.v1]]
        try {
            ::GX::interactiveDocumentResourceAppend $writer [encoding convertto utf-8 $meaning]
            dict set resources interpretation [::GX::interactiveDocumentResourceFinalize $writer];set writer {}
        } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
        if {[dict get [dict get $resources values] size_bytes]!=40*[dict get $raw point_count]} {error {Uncertainty result has incomplete physical columns}}
        if {[dict get [_ownedDocumentRead $document] sha256] ne $expectedSha||[sourceResolve $document] ne $source} {error {Digitizer source changed during uncertainty review}}
        set review [dict create schema gxtxt.digitizer_review.v1 document_id $document document_sha256 $expectedSha session_token [sessionToken] meaning $meaning resources $resources]
        dict set uncertaintyReviews $key $review
        return $review
    } finally {::GX::resourceManagementRelease [dict get $allocation id];::GX::resourceManagementCleanup [list [dict get $allocation id]]}
}
proc ::GX::CurveDigitizerCompanion::uncertaintyPublicationReview {document expectedSha rows} {
    variable uncertaintyReviews
    set key [list [sessionToken] $document $expectedSha]
    if {![dict exists $uncertaintyReviews $key]} {error {Save and review the current uncertainty declaration before publishing}}
    set review [uncertaintyReview $document $expectedSha]
    set n [dict get $review meaning summary point_count]
    if {[dict get $rows count]!=$n||[llength [dict get $rows point_id]]!=$n} {error {Publication rows differ from the reviewed original points}}
    set ref [dict get $review resources points]
    set lines [split [string trimright [encoding convertfrom utf-8 [::GX::interactiveDocumentResourceReadChunk $ref 0 [dict get $ref size_bytes]]] "\n"] "\n"]
    set i 0
    foreach line $lines {
        set values {};foreach part [split $line "\t"] {lappend values [encoding convertfrom utf-8 [binary decode base64 -strict $part]]}
        lassign $values curve label point index family
        foreach {field value} [list curve_id $curve curve_label $label point_id $point point_index $index] {if {[lindex [dict get $rows $field] $i] ne $value} {error {Publication point identity/order differs from the uncertainty review}}}
        incr i
    }
    set ref [dict get $review resources values]
    binary scan [::GX::interactiveDocumentResourceReadChunk $ref 0 [dict get $ref size_bytes]] q* values
    foreach {field offset} {x 0 y 1} {
        for {set i 0} {$i<$n} {incr i} {if {[lindex [dict get $rows $field] $i]!=[lindex $values [expr {$offset*$n+$i}]]} {error {Publication coordinates differ from the reviewed calibration}}}
    }
    set columns {};foreach {name offset} {sigma_x 2 sigma_y 3 covariance_xy 4} {dict set columns $name [lrange $values [expr {$offset*$n}] [expr {($offset+1)*$n-1}]]}
    dict set review columns $columns
    return $review
}
proc ::GX::CurveDigitizerCompanion::validateUncertaintyBinding {binding} {
    if {[dict get $binding schema] ne "gxtxt.digitizer_publication_binding.v1"||![regexp {^[a-f0-9]{64}$} [dict get $binding payload_sha256]]} {error {Invalid retained digitization publication identity}}
    set n [dict get $binding point_count]
    if {![string is integer -strict $n]||$n<1||$n>4096} {error {Invalid retained digitization point count}}
    set resources [dict get $binding resources]
    foreach role {configuration points state values interpretation} {::GX::interactiveDocumentResourceInfo [dict get $resources $role]}
    set reference [dict get $resources interpretation]
    if {[dict get $reference size_bytes]>1048576||[dict get $reference metadata format] ne "gxtxt.digitization_interpretation.tcldict.v1"} {error {Invalid retained digitization meaning resource}}
    set meaning [encoding convertfrom utf-8 [::GX::interactiveDocumentResourceReadChunk $reference 0 [dict get $reference size_bytes]]]
    ::GX::StatisticsV1::validate $meaning
    if {[dict get $meaning schema] ne "gxtxt.digitization_interpretation.v1"||[dict get $meaning summary point_count]!=$n||[dict get $meaning context source_document_sha256] ne [dict get $resources configuration sha256]||[dict get $meaning context point_ids_sha256] ne [dict get $resources points sha256]||[dict get $resources values size_bytes]!=40*$n} {error {Retained digitization meaning lost its point/calibration binding}}
    foreach key {x_variable_id y_variable_id sigma_x_variable_id sigma_y_variable_id point_id_variable_id} {if {[dict get $binding $key] eq {}} {error {Retained digitization variable identity is missing}}}
    return $meaning
}
proc ::GX::CurveDigitizerCompanion::publicationUncertainty {dataset} {
    set metadata [::GX::datasetMetadataRead [_requireSession] $dataset]
    if {![dict exists $metadata curve_digitizer.uncertainty_binding]} {return {}}
    set binding [dict get $metadata curve_digitizer.uncertainty_binding]
    set meaning [validateUncertaintyBinding $binding]
    set identity [::GX::curveSourceDatasetIdentity [_requireSession] $dataset]
    if {[dict get $binding dataset_id] ne $dataset||[dict get $binding payload_sha256] ne [dict get $identity sha256]} {error {Digitizer Dataset bytes changed after uncertainty publication}}
    set schema {};foreach variable [::GX::datasetVariableSchemaV3 $dataset] {dict set schema [dict get $variable variable_id] $variable}
    lassign [dict get $meaning summary coordinate_units] ux uy
    foreach {field unit} [list x_variable_id $ux y_variable_id $uy sigma_x_variable_id $ux sigma_y_variable_id $uy] {
        set variable [dict get $schema [dict get $binding $field]]
        if {![dict get $variable enabled]||[dict get $variable unit] ne $unit||[dict get $variable rank]!=1} {error {Digitizer Variable units, availability or shape changed}}
    }
    return [dict create binding $binding meaning $meaning source_identity $identity]
}
proc ::GX::CurveDigitizerCompanion::publishCovariance {dataset target axis} {
    set capture [publicationUncertainty $dataset]
    if {$capture eq {}||$axis ni {x y}} {error {Choose a reviewed digitizer Dataset and physical X or Y covariance}}
    set meaning [dict get $capture meaning];set n [dict get $meaning summary point_count]
    if {$n>512} {error {Full response covariance is bounded to 512 original points; shared factors remain retained}}
    set orientation [expr {$axis eq "y"?"y_of_x":"x_of_y"}]
    set plan [::GX::StatisticsV1::digitizationFitPlan $meaning full_response_covariance $orientation]
    set unit [dict get $meaning columns sigma_$axis unit];set squared "$unit*$unit"
    set conversion [::GX::unitRegistryDifferentialRatioPlan $squared $unit $unit]
    if {[dict get $conversion status] ne "value"||abs([dict get $conversion scale]-1)>1e-14} {error {The Unit Registry cannot validate these squared physical units; supply a supported physical axis unit before publication}}
    set allocation [::GX::resourceManagementAllocate scientific_transport [dict create kind directory session $::GX::currentSession lifetime computation]]
    set workspace [dict get $allocation path]
    try {
        set reader [::GX::interactiveDocumentResourceOpenReader [dict get $capture binding resources state]];set channel {}
        try {
            set channel [open [file join $workspace state.mat] {WRONLY CREAT EXCL}];fconfigure $channel -translation binary -encoding binary
            while 1 {set page [::GX::interactiveDocumentResourceNext $reader];puts -nonewline $channel [dict get $page bytes];if {[dict get $page eof]} break}
        } finally {if {$channel ne {}} {close $channel};::GX::interactiveDocumentResourceCloseReader $reader}
        set empty [::GX::ScientificTransportv1::empty]
        set result [dict get [::GX::ScientificTransportv1::call viewer.curve_digitizer gxtxt_digitizer_uncertainty_v1 digitizer covariance $empty [::GX::ScientificTransportv1::text $axis] $empty [::GX::ScientificTransportv1::struct [dict create workspace [::GX::ScientificTransportv1::text $workspace]]]] values]
        if {[dict get $result source_state_sha256] ne [dict get $meaning summary state_sha256]||[dict get $result point_count]!=$n||[publicationUncertainty $dataset] ne $capture} {error {Digitizer covariance source changed during materialization}}
        set document [dict get $meaning context source_document_id]
        set resource [::GX::interactiveDocumentResourceImportNumeric $document [file join $workspace covariance.bin] [dict create format gxtxt.numeric_array_le.v1 dtype float64 endian little order F shape [list $n $n] unit $squared]]
        set variables [list [dict create variable_id covariance schema [dict create dtype float64 dimension_ids {source_row;source_column} unit $squared] resource $resource]]
        set published [::GX::datasetPublicationV2PublishManagedVariables $::GX::currentSession viewer.curve_digitizer [dict create dataset_id $target contract table.generic storage hdf5 producer_version 1.2.4 source_dataset_ids [list $dataset] provenance {Original point order on both covariance axes; conditional response covariance ignores predictor uncertainty}] [dict create source_row $n source_column $n] $variables]
        set binding [dict create schema gxtxt.digitizer_covariance_binding.v1 source [dict get $capture binding] source_identity [dict get $capture source_identity] axis $axis variable_id covariance resource $resource fit_plan $plan covariance_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $target]]
        ::GX::datasetMetadataUpdate $::GX::currentSession $target [dict create curve_digitizer.covariance_binding $binding]
        return $published
    } finally {::GX::resourceManagementRelease [dict get $allocation id];::GX::resourceManagementCleanup [list [dict get $allocation id]]}
}
proc ::GX::CurveDigitizerCompanion::covariancePublication {dataset} {
    set metadata [::GX::datasetMetadataRead [_requireSession] $dataset]
    if {![dict exists $metadata curve_digitizer.covariance_binding]} {return {}}
    set binding [dict get $metadata curve_digitizer.covariance_binding]
    set meaning [validateUncertaintyBinding [dict get $binding source]]
    if {[dict get $binding schema] ne "gxtxt.digitizer_covariance_binding.v1"||[::GX::curveSourceDatasetIdentity [_requireSession] $dataset] ne [dict get $binding covariance_identity]} {error {Published digitizer covariance identity changed}}
    ::GX::interactiveDocumentResourceInfo [dict get $binding resource]
    set orientation [expr {[dict get $binding axis] eq "y"?"y_of_x":"x_of_y"}]
    if {[::GX::StatisticsV1::digitizationFitPlan $meaning full_response_covariance $orientation] ne [dict get $binding fit_plan]} {error {Published digitizer covariance interpretation changed}}
    return $binding
}
proc ::GX::CurveDigitizerCompanion::uncertaintyReport {document expectedSha} {
    set review [uncertaintyReview $document $expectedSha]
    set meaning [dict get $review meaning]
    set text [::GX::StatisticsV1::digitizationReport $meaning]
    foreach kind {sigma sigma_xy full_response_covariance} {
        set plan [::GX::StatisticsV1::digitizationFitPlan $meaning $kind y_of_x]
        append text "\n\n$kind: [dict get $plan status] — [dict get $plan reason]"
    }
    set reference [dict get $review resources values];set n [dict get $meaning summary point_count]
    binary scan [::GX::interactiveDocumentResourceReadChunk $reference 0 [dict get $reference size_bytes]] q* values
    append text "\n\nFirst physical standard uncertainties (X, Y):"
    for {set i 0} {$i<min(4,$n)} {incr i} {append text "\n[expr {$i+1}]: [lindex $values [expr {2*$n+$i}]], [lindex $values [expr {3*$n+$i}]]"}
    return $text
}
