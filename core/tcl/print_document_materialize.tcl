# SPDX-License-Identifier: GPL-3.0-or-later
# Worker-side adapter: canonical scientific owners supply immutable print inputs.
lassign $argv framework session requestFile outputFile
set argv0 __gxtxt_print_materializer__
source [file join $framework gxtxt_pipeline.tcl]
proc readData {path} {set f [open $path r];fconfigure $f -encoding utf-8;try {return [string trim [read $f]]} finally {close $f}}
proc watchFile {path} {
    if {![file isfile $path]} {error "Scientific source is unavailable: $path"}
    dict set ::manifest [file normalize $path] [::GX::sha256File $path]
}
proc watchOptional {path} {
    if {[file exists $path]} {watchFile $path} else {dict set ::manifest [file normalize $path] absent:v1}
}
proc watchDataset {id} {
    set payload [::GX::sessionInspectionDatasetPayload $id]
    if {[dict get $payload path] ne {}} {watchFile [dict get $payload path]}
    dict set ::sourceGuards $id [::GX::datasetViewerScientificIdentity $id]
    return $payload
}
try {
    ::GX::defaults;::GX::loadModuleCatalog
    set ::GX::currentSession [file normalize $session]
    ::GX::loadManifest [file join $session metadata manifest.ini]
    ::GX::loadDatasetRegistry $session
    set request [readData $requestFile];set recipe [::GX::printRecipeValidate [dict get $request recipe]]
    set ::manifest {};set ::sourceGuards {};set items {};set index 0
    if {[dict exists $request nodes]} {dict for {id node} [dict get $request nodes] {::GX::scientificExecutionNodeRegister $id $node}}
    foreach item [dict get $recipe items] {
        incr index
        set kind [dict get $item source_kind];set id [dict get $item source_id];set presentation [dict get $item presentation]
        set expected [dict get $item source_signature]
        if {$kind eq {literal}} {
            # Authored poster content belongs to the validated recipe, not to a
            # fabricated scientific Dataset/Graph or scientific source token.
            set signature {}
        } elseif {$kind eq {dataset}} {
            set signature [::GX::printRecipeSourceSignature $kind $id]
            if {$signature ne $expected} {error "Dataset $id changed; update the composition source."}
        } else {
            set path [file normalize [file join $session $id]]
            set analysis [file normalize [file join $session analysis]]
            if {[string first "$analysis/" "$path/"]!=0 || ![file isfile $path] || $path ne [lindex $expected 1]} {error {Graph source is unavailable in this Session.}}
            file stat $path st
            if {[list $st(size) $st(mtime) $st(ctime) $st(ino)] ne [lrange $expected 2 5]} {error "Graph $id changed; update the composition source."}
            dict for {source identity} [lindex $expected 8] {if {[::GX::datasetViewerScientificIdentity $source] ne $identity} {error {A Graph Dataset dependency changed.}}}
            set signature $expected
        }
        set result [dict create id [dict get $item id] kind $presentation caption [dict get $item caption] source_id $id]
        foreach key {frame style text} {if {[dict exists $item $key]} {dict set result $key [dict get $item $key]}}
        set options [dict get $item options]
        set target [file join [file dirname $outputFile] item_$index]
        if {$kind eq {literal}} {
            dict set result text [dict get $item text]
        } elseif {$kind eq {dataset}} {
            set payload [watchDataset $id]
            switch $presentation {
                table {
                    set variables [dict get $options variables];set columns {}
                    foreach variable $variables {set schema [::GX::datasetVariableV3ById $id $variable];lappend columns [dict create variable_id $variable label [::GX::datasetPublicationV2DictDefault $schema label $variable] unit [dict get $schema unit]]}
                    if {$variables eq {}} {error {Choose at least one table Variable ID.}}
                    set stream [::GX::tableStreamOpenDataset $session $id $variables 256 [dict create start [dict get $options start] count [dict get $options count] numeric_transport values]]
                    set rows {};set sourceRows {}
                    try {
                        while {1} {
                            set chunk [::GX::tableStreamNext $stream]
                            for {set row 0} {$row<[dict get $chunk nrows]} {incr row} {
                                set values {};foreach variable $variables {lappend values [lindex [dict get $chunk values $variable] $row]}
                                lappend rows $values;lappend sourceRows [expr {[dict get $chunk offset]+$row}]
                            }
                            if {[string bytelength $rows]>16777216} {error {Table projection exceeds 16 MiB; choose a smaller explicit range.}}
                            if {[dict get $chunk eof]} break
                        }
                    } finally {::GX::tableStreamClose $stream}
                    dict set result columns $columns;dict set result rows $rows;dict set result source_rows $sourceRows
                }
                image - pdf - text {
                    if {[dict get $payload path] eq {}} {error {Remote original media transfer is not declared; choose the bounded metadata representation.}}
                    set path [dict get $payload path]
                    if {[file size $path]>67108864} {error {Original media exceeds the 64 MiB print limit.}}
                    if {$presentation eq {text}} {
                        if {[file size $path]>8388608} {error {Text exceeds the 8 MiB print limit.}}
                        set f [open $path r];fconfigure $f -encoding utf-8;try {dict set result text [read $f]} finally {close $f}
                    } else {append target [file extension $path];file copy $path $target;dict set result path $target}
                    if {[dict exists $options pdf_pages]} {dict set result pdf_pages [dict get $options pdf_pages]}
                }
                metadata {
                    set descriptor [::GX::printContentDescribe dataset $id]
                    set text "Dataset $id\n[dict get $descriptor title]\nKind: [dict get $descriptor kind]\nScientific identity: $expected\n"
                    dict set result text $text
                }
                xy {
                    ::GX::graphNativeRendererRequire
                    set spec [::GX::PlotDatasetAPIv4::newSpec -graph_id plot.dataset.xy -title [dict get $item caption]]
                    dict set spec panels [list [dict create id main title {} axes {} annotations {} series [list [dict create id source dataset_id $id x_variable_id [dict get $options x_variable_id] y_variable_id [dict get $options y_variable_id] axis left]]]]
                }
                default {error {No print materializer exists for this Dataset representation.}}
            }
        } else {
            set path [lindex $signature 1];watchFile $path
            set reference [lindex $signature 6]
            if {$reference ne {}} {watchOptional [::GX::graphResourcePath $reference metadata]}
            foreach source [dict keys [lindex $expected 8]] {watchDataset $source}
            set annotation [::GX::annotationPathForPlot $path]
            watchOptional $annotation
            if {[file isfile $annotation]} {
                ::GX::annotationRenderTo $path $target.png
                dict set result kind image;dict set result path $target.png
            } elseif {$reference ne {} && [::GX::datasetPublicationV2DictDefault [lindex $expected 7] renderer_owner legacy] eq {PLOT_DATASET_API_v4} && [dict get $reference kind] eq {provider}} {
                # The GUI explicitly freezes unsaved presentation using its owner.
                ::GX::graphNativeRendererRequire
                set spec [lindex $expected 9]
            } else {
                file copy $path $target[file extension $path]
                dict set result kind [expr {[string tolower [file extension $path]] eq {.pdf} ? {pdf} : {image}}]
                dict set result path $target[file extension $path]
            }
        }
        if {[info exists spec]} {
            if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {
                # Recreate the frozen public PlotSpec only in owned disposable
                # Session storage. No GUI-wide Manifest serialization or write
                # to the original Graph/Session is needed, including unsaved
                # source bindings. Public Portable and Plot snapshot owners
                # retain all scientific interpretation and rendering.
                set archives {};set bytes 0
                foreach source [dict keys [lindex $expected 8]] {
                    set payload [watchDataset $source]
                    if {[dict get $payload path] eq {} || [file size [dict get $payload path]]>67108864} {error {Native3D print capture requires an available local source of at most 64 MiB.}}
                    incr bytes [file size [dict get $payload path]]
                    if {$bytes>67108864} {error {Native3D print source capture exceeds its 64 MiB total limit.}}
                    set archive $target.$source.zip
                    ::GX::portableResourceExportDataset $source $archive
                    dict set archives $source $archive
                }
                set page [dict get $recipe page]
                lassign [dict get {A4 {210 297} A3 {297 420} LETTER {215.9 279.4}} [dict get $page paper]] pw ph
                if {[dict get $page orientation] eq {landscape}} {set pw $ph}
                set cellWidth [expr {($pw-2*[dict get $page margin_mm]-([dict get $page columns]-1)*[dict get $page gap_mm])/[dict get $page columns]}]
                if {$cellWidth<70} {error {Native3D scientific axes require a print cell at least 70 mm wide; choose fewer artwork columns.}}
                dict set spec native_presentation graphics width_px 2400
                dict set spec native_presentation graphics height_px 1800
                dict set spec native_presentation graphics dpi [expr {min(600,int(2400*25.4/$cellWidth))}]
                dict set spec native_presentation graphics font_unit pt
                foreach {field minimum} {font_size 10 axis_label_font_size 12 title_font_size 14} {
                    set size [::GX::datasetPublicationV2DictDefault [dict get $spec native_presentation graphics] $field $minimum]
                    if {![string is double -strict $size] || [catch {expr {abs($size)<Inf}} finite] || !$finite} {set size $minimum}
                    dict set spec native_presentation graphics $field [expr {max($minimum,$size)}]
                }
                set originalSession $::GX::currentSession
                try {
                    ::GX::datasetPreviewCacheInit
                    ::GX::configurationSet preview.cache_enabled 0
                    set ::GX::cfg(output_root) [file join [file dirname $outputFile] derived_sessions]
                    ::GX::createNewSession print_native3d_$index
                    dict for {source archive} $archives {::GX::portableResourceImport $archive [dict create dataset_id $source]}
                    set ownReference [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
                    ::GX::PlotDatasetAPIv4::render $ownReference
                    set ownArtifact [dict get [::GX::PlotDatasetAPIv4::artifacts $ownReference] graph_artifact]
                    set capture $target.native3d
                    ::GX::PlotDatasetAPIv4::captureForArtifact $ownArtifact $capture
                    set artwork [file join $capture graph.png]
                } finally {
                    set ::GX::currentSession $originalSession
                    ::GX::loadManifest [file join $originalSession metadata manifest.ini]
                    ::GX::loadDatasetRegistry $originalSession
                }
                dict set result kind image;dict set result path $artwork
            } else {
                package require Tk;wm withdraw .
                ::GX::PlotDatasetAPIv4::widgetCreate .printsource $spec
                try {::GX::PlotDatasetAPIv4::widgetExport .printsource $target.pdf 720 500} finally {destroy .printsource}
                dict set result kind pdf;dict set result path $target.pdf
            }
            unset spec
        }
        # Recheck actual payloads after materialization; no read can bless a mixed revision.
        dict for {path sha} $::manifest {
            if {$sha eq {absent:v1}} {
                if {[file exists $path] || ![catch {file type $path}]} {error {A scientific source presentation changed while the document was being frozen.}}
            } elseif {[::GX::sha256File $path] ne $sha} {error {A scientific source changed while the document was being frozen.}}
        }
        lappend items $result
        if {[string bytelength $items]>33554432} {error {Frozen print content exceeds 32 MiB; choose fewer items or smaller ranges.}}
        set temporaryBytes 0
        foreach path [::GX::walkFiles [file dirname $outputFile]] {incr temporaryBytes [file size $path];if {$temporaryBytes>402653184} {error {Print preparation exceeds its 384 MiB temporary-file limit.}}}
    }
    set f [open $outputFile {WRONLY CREAT EXCL}];fconfigure $f -encoding utf-8
    puts $f [dict create schema gxtxt.print_materialized.v1 title [dict get $recipe title] page [dict get $recipe page] items $items manifest $::manifest guards $::sourceGuards nodes [::GX::datasetPublicationV2DictDefault $request nodes {}]];close $f
} on error {message options} {puts stderr [dict get $options -errorinfo];exit 1}
exit 0
