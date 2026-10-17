# SPDX-License-Identifier: GPL-3.0-or-later
# Printing document authority; existing CORE Dataset/Graph/Preview/Workspace,
# Resource Management and Script Job owners retain their scientific roles.
namespace eval ::GX::PrintDocument {variable cups {};variable ignored 0}
proc ::GX::printRecipeNew {} {
    return [dict create schema gxtxt.print_recipe.v1 title {Scientific print composition} page [dict create paper A4 orientation portrait rows 1 columns 1 margin_mm 12 gap_mm 5 captions 1] items {}]
}
proc ::GX::printRecipeValidate {recipe} {
    foreach key {schema title page items} {if {![dict exists $recipe $key]} {error "Print recipe requires '$key'."}}
    foreach key [dict keys $recipe] {if {$key ni {schema title page items}} {error "Unknown print recipe field '$key'."}}
    if {[dict get $recipe schema] ne {gxtxt.print_recipe.v1} || [string bytelength $recipe]>8388608 || [llength [dict get $recipe items]]>200} {error {Unsupported or oversized print recipe (8 MiB / 200 items).}}
    if {[regexp {[\r\n]} [dict get $recipe title]] || [string length [dict get $recipe title]]>200} {error {Print title must be a single line of at most 200 characters.}}
    set page [dict get $recipe page]
    if {[dict get $page paper] ni {A4 A3 LETTER} || [dict get $page orientation] ni {portrait landscape}} {error {Choose a supported paper size and orientation.}}
    foreach key [dict keys $page] {if {$key ni {paper orientation rows columns margin_mm gap_mm captions}} {error "Unknown print page field '$key'."}}
    foreach key {rows columns} {if {![string is integer -strict [dict get $page $key]] || [dict get $page $key]<1 || [dict get $page $key]>4} {error {Print grid rows/columns must be from 1 to 4.}}}
    foreach key {margin_mm gap_mm} {set n [dict get $page $key];if {![string is double -strict $n] || [catch {expr {abs($n)<Inf}} finite] || !$finite || $n<0 || $n>60} {error {Print margins and spacing must be finite values from 0 to 60 mm.}}}
    if {![string is boolean -strict [dict get $page captions]]} {error {Print captions must be boolean.}}
    set ids {}
    foreach item [dict get $recipe items] {
        foreach key {id source_kind source_id presentation source_signature options caption} {if {![dict exists $item $key]} {error "Print item requires '$key'."}}
        foreach key [dict keys $item] {if {$key ni {id source_kind source_id presentation source_signature options caption}} {error "Unknown print item field '$key'."}}
        set id [dict get $item id]
        if {![regexp {^print_[a-zA-Z0-9_]+$} $id] || $id in $ids} {error {Duplicate or invalid print item identity.}}
        lappend ids $id
        if {[dict get $item source_kind] ni {dataset graph} || [dict get $item presentation] ni {table xy image pdf text metadata graph}} {error {Unsupported print source or representation.}}
        if {[dict get $item source_kind] eq {dataset} && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $item source_id]]} {error {Invalid canonical Dataset identity.}}
        if {[regexp {[\r\n]} [dict get $item caption]] || [string length [dict get $item caption]]>400} {error {Print caption must be a single line of at most 400 characters.}}
        set options [dict get $item options]
        foreach key [dict keys $options] {if {$key ni {variables start count x_variable_id y_variable_id pdf_pages}} {error "Unknown print item option '$key'."}}
        foreach key {start count} {if {[dict exists $options $key] && (![string is entier -strict [dict get $options $key]] || [dict get $options $key]<[expr {$key eq {count} ? 1 : 0}] || ($key eq {count} && [dict get $options $key]>10000))} {error {Choose an explicit table range: nonnegative start, count 1–10000.}}}
        if {[dict exists $options variables] && [llength [dict get $options variables]]>64} {error {A print table accepts at most 64 explicitly selected variables.}}
    }
    return [dict create {*}$recipe]
}
proc ::GX::printRecipeHistoryValidate {record} {printRecipeValidate [dict get $record base];return 1}
proc ::GX::printRecipeHistoryCreate {recipe} {
    scientificRecipeHostRegister framework.printing [dict create capture ::GX::printRecipeNew validate ::GX::printRecipeHistoryValidate replay ::GX::scientificHistoryState]
    return [scientificHistoryCreate framework.printing [printRecipeValidate $recipe]]
}
proc ::GX::printRecipeHistoryEdit {history recipe description} {
    printRecipeValidate $recipe
    if {[dict get $history cursor]!=[llength [dict get $history steps]]} {set history [scientificHistoryBranch framework.printing $history [dict get $history cursor]]}
    return [scientificHistoryAppend framework.printing $history $recipe $description]
}
proc ::GX::printRecipeDocumentSave {recipe history {id {}} {expected {}}} {
    set recipe [printRecipeValidate $recipe];scientificHistoryValidate framework.printing $history
    set payload [dict create schema gxtxt.print_composition.v1 recipe $recipe history $history]
    if {$id eq {}} {return [interactiveDocumentCreate framework.printing print_composition gxtxt.print_composition.v1 1 $payload]}
    set current [interactiveDocumentRead $id]
    if {[dict get $current module_id] ne {framework.printing} || [dict get $current provider_id] ne {print_composition} || $expected ne [list [dict get $current generation] [dict get $current revision] [dict get $current sha256]]} {error {Print composition changed in another editor; reopen before saving.}}
    return [interactiveDocumentUpdate $id $payload]
}
proc ::GX::printRecipeDocumentRead {id} {
    set doc [interactiveDocumentRead $id]
    if {[dict get $doc module_id] ne {framework.printing} || [dict get $doc provider_id] ne {print_composition} || [dict get $doc format] ne {gxtxt.print_composition.v1}} {error {This document is not a Print composition.}}
    printRecipeValidate [dict get $doc payload recipe]
    return $doc
}
proc ::GX::printRecipeSourceSignature {kind id} {
    if {$kind eq {dataset}} {return [datasetViewerScientificIdentity $id]}
    if {$kind ne {graph} || $::GX::currentSession eq {}} {error {Choose a current Dataset or Graph.}}
    set path [file normalize [expr {[file pathtype $id] eq {absolute} ? $id : [file join $::GX::currentSession $id]}]];set root [file normalize [file join $::GX::currentSession analysis]]
    if {[string first "$root/" "$path/"]!=0 || ![file isfile $path]} {error {Graph artwork is unavailable in this Session.}}
    file stat $path st
    set reference {};set metadata {}
    if {![catch {graphResourceRefForPath $path} found]} {set reference $found;set metadata [graphMetadataRead $reference]}
    set annotation [annotationPathForPlot $path]
    if {[file isfile $annotation]} {file stat $annotation ast;dict set metadata print_annotation_stamp [list $annotation $ast(size) $ast(mtime) $ast(ctime) $ast(ino)]}
    set spec {};set dependencies {}
    if {$reference ne {} && [graphRendererOwner $reference] eq {PLOT_DATASET_API_v4} && [dict get $reference kind] eq {provider}} {
        graphNativeRendererRequire
        set spec [graphRendererEffectiveSpec $reference [::GX::PlotDatasetAPIv4::loadSpec $reference]]
        if {[dict exists $spec dataset_id]} {set source [dict get $spec dataset_id];dict set dependencies $source [datasetViewerScientificIdentity $source]}
        foreach panel [datasetPublicationV2DictDefault $spec panels {}] {
            foreach series [dict get $panel series] {
                set source [dict get $series dataset_id]
                dict set dependencies $source [datasetViewerScientificIdentity $source]
                if {[dict exists $series cell_field nodes_dataset_id]} {set nodes [dict get $series cell_field nodes_dataset_id];dict set dependencies $nodes [datasetViewerScientificIdentity $nodes]}
            }
        }
    } elseif {$reference ne {} && [dict get $reference kind] eq {provider}} {
        set spec [graphRendererEffectiveSpec $reference [dict create graph_id [dict get $reference graph_id] panels {}]]
    }
    return [list graph $path $st(size) $st(mtime) $st(ctime) $st(ino) $reference $metadata $dependencies $spec]
}
proc ::GX::printContentDescribe {kind id} {
    if {$kind eq {graph}} {set path [expr {[file pathtype $id] eq {absolute} ? $id : [file join $::GX::currentSession $id]}];return [dict create source_kind graph source_id $id title [graphDisplayTitle $path] kind {Published Graph artwork} representations {graph} default graph reason {Full published artwork; cached thumbnails are not print sources.}]}
    if {$kind ne {dataset} || [datasetField $id id {}] eq {}} {error {Dataset is unavailable.}}
    set format [string tolower [datasetField $id format]];set media [string tolower [datasetField $id media_type]]
    set representations {};set reason {};set variables [datasetVariableSchemaV3 $id];set tableVariables {};set xyVariables {}
    foreach variable $variables {
        if {[dict get $variable rank]!=1 || [dict get $variable dtype] ni [tableStreamKnownDtypes]} continue
        lappend tableVariables [dict get $variable variable_id]
        if {[dict get $variable dtype] ne {string}} {lappend xyVariables [dict get $variable variable_id]}
    }
    if {[string match image/* $media] || $format in {png jpg jpeg tif tiff bmp}} {set representations {image metadata}} elseif {$media eq {application/pdf} || $format eq {pdf}} {set representations {pdf metadata}} elseif {[string match text/* $media] && $format ni {csv tsv}} {set representations {text metadata}} else {
        if {[llength $tableVariables]>0} {set representations {table};if {[llength $xyVariables]>=2} {lappend representations xy};lappend representations metadata} else {set representations {metadata};set reason {No supported scientific paper projection is declared. Metadata synopsis is available explicitly.}}
    }
    if {[datasetProviderFor $id] eq {remote} && [lindex $representations 0] in {image pdf text}} {set representations {metadata};set reason {Bounded remote Preview is available, but no original-media print transfer is declared.}}
    return [dict create source_kind dataset source_id $id title [datasetField $id display_name $id] kind [datasetField $id kind] format $format media_type $media variables $variables table_variables $tableVariables xy_variables $xyVariables row_count [datasetField $id row_count {}] representations $representations default [lindex $representations 0] reason $reason]
}
proc ::GX::printDocumentApiInfo {} {
    return [dict create api_id PRINT_DOCUMENT_API_v1 api_version 1 authority services/printing operations {printRecipeNew printRecipeValidate printRecipeHistoryCreate printRecipeHistoryEdit printRecipeDocumentSave printRecipeDocumentRead printRecipeSourceSignature printContentDescribe printDocumentRequest printDocumentCancel printDocumentRelease printDocumentSourcePreview printDocumentMediaInfo printCupsRequest printCupsQuery printCupsCancel printCupsState} transport SCRIPT_JOB_API_v1 cups_lifetime bounded_auxiliary scientific_authority 0]
}
proc ::GX::printCupsRequest {operation arguments callback} {
    set counts {discover 2 capabilities 2 submit 3 job_status 2 cancel_job 1}
    if {![dict exists $counts $operation]} {error {Unsupported public CUPS operation.}}
    set timeout [configurationGet printing.cups_timeout_ms]
    if {![string is integer -strict $timeout] || $timeout<250 || $timeout>30000} {error {CUPS timeout must be 250–30000 ms.}}
    set source [datasetPublicationV2DictDefault $arguments source_resource {}]
    dict unset arguments source_resource
    if {$source ne {}} {dict incr ::GX::PrintDocument::leases $source;set callback [list ::GX::_printCupsResourceDone $source $callback]}
    set allowed [dict get {discover {} capabilities {printer} submit {printer capability_sha256 pdf pdf_sha256 copies duplex options pages source_manifest} job_status {printer job_id} cancel_job {job_id}} $operation]
    foreach key [dict keys $arguments] {if {$key ni $allowed} {error "Unknown CUPS argument '$key'."}}
    set request [dict merge $arguments [dict create operation $operation timeout_ms $timeout]]
    set options [dict create timeout_ms [expr {$timeout*[dict get $counts $operation]+1500+($operation eq {submit} ? 20000 : 0)}] max_bytes 2097152 process_group 1 ui_lifetime 1 label "CUPS $operation"]
    return [scriptJobAsync [list [runtimeToolRequired python] -B [file join $::GX::scriptDir services printing gxtxt_print_request.py]] $request $callback $options]
}
proc ::GX::printCupsQuery {channel operation arguments callback} {
    variable ::GX::PrintDocument::cups
    if {$channel ni {discovery capabilities submission status}} {error {Unknown CUPS request channel.}}
    set entry [datasetPublicationV2DictDefault $cups $channel {generation 0 request {} pending {} operation {} last {}}]
    dict incr entry generation
    dict set entry pending [dict create generation [dict get $entry generation] operation $operation arguments $arguments callback $callback]
    dict set cups $channel $entry
    if {[dict get $entry request] ne {}} {scriptJobRequestCancel [dict get $entry request]} else {_printCupsStart $channel}
    return [dict create channel $channel generation [dict get $entry generation]]
}
proc ::GX::_printCupsStart {channel} {
    variable ::GX::PrintDocument::cups
    set entry [dict get $cups $channel];set pending [dict get $entry pending]
    if {$pending eq {}} return
    dict set entry pending {};dict set entry operation [dict get $pending operation]
    dict set entry request [printCupsRequest [dict get $pending operation] [dict get $pending arguments] [list ::GX::_printCupsDone $channel [dict get $pending generation] [dict get $pending callback]]]
    dict set cups $channel $entry
}
proc ::GX::_printCupsDone {channel generation callback response} {
    variable ::GX::PrintDocument::cups;variable ::GX::PrintDocument::ignored
    if {![dict exists $cups $channel]} return
    set entry [dict get $cups $channel];dict set entry request {}
    set deliver [expr {$generation==[dict get $entry generation] && [dict get $entry pending] eq {}}]
    if {$deliver} {dict set entry last [dict create generation $generation response $response verified_at [clock seconds]]} else {incr ignored}
    dict set cups $channel $entry
    if {[llength [info commands winfo]] && ![winfo exists .]} {return}
    if {[dict get $entry pending] ne {}} {_printCupsStart $channel}
    if {$deliver && $callback ne {}} {uplevel #0 [list {*}$callback [dict merge $response [dict create generation $generation]] ]}
}
proc ::GX::printCupsCancel {channel} {
    variable ::GX::PrintDocument::cups
    if {![dict exists $cups $channel]} {return 0}
    set entry [dict get $cups $channel];dict incr entry generation;dict set entry pending {}
    dict set cups $channel $entry
    if {[dict get $entry request] ne {}} {scriptJobRequestCancel [dict get $entry request]}
    return 1
}
proc ::GX::printCupsState {{channel {}}} {
    if {$channel eq {}} {return [dict create channels $::GX::PrintDocument::cups ignored_stale_responses $::GX::PrintDocument::ignored]}
    return [datasetPublicationV2DictDefault $::GX::PrintDocument::cups $channel {generation 0 request {} pending {} last {}}]
}

# Print requests allocate before spawning. Resource leases outlive their workers;
# cancellation uses the same Script Job transport as CUPS and all host adapters.
namespace eval ::GX::PrintDocument {variable requests {};variable serial 0;variable leases {};variable retired {}}
proc ::GX::printDocumentRequest {operation arguments callback} {
    variable ::GX::PrintDocument::requests;variable ::GX::PrintDocument::serial;variable ::GX::PrintDocument::leases
    if {$operation ni {compose page thumbnails verify export source_preview media_info}} {error {Unknown print document operation.}}
    set token print-document#[incr serial]
    set resource [datasetPublicationV2DictDefault $arguments source_resource {}]
    if {$resource ne {}} {dict incr leases $resource}
    dict set requests $token [dict create operation $operation arguments $arguments callback $callback cancelled 0 request {} resource {} source_resource $resource]
    set reservation [dict get {compose 805306368 page 67108864 thumbnails 33554432 source_preview 16777216 media_info 1048576 verify 1048576 export 1048576} $operation]
    resourceManagementAsync allocate [list subsystem printing kind directory category temporary lifetime document expected_bytes $reservation retention_seconds 0] [list ::GX::_printDocumentAllocated $token]
    return $token
}
proc ::GX::_printDocumentAllocated {token code allocation} {
    variable ::GX::PrintDocument::requests
    if {![dict exists $requests $token]} return
    if {$code || ![dict exists $allocation id]} {_printDocumentDone $token [dict create ok 0 error "Print resource allocation failed: $allocation"];return}
    set record [dict get $requests $token];dict set record resource $allocation;dict set requests $token $record
    if {[dict get $record cancelled]} {_printDocumentDone $token {ok 0 error {Print request cancelled.}};return}
    set arguments [dict get $record arguments];dict unset arguments source_resource
    set data [dict merge $arguments [dict create operation [dict get $record operation] root [dict get $allocation path]]]
    set worker [file join $::GX::scriptDir services printing gxtxt_print_document_request.py]
    set command [list [runtimeToolRequired python] -B $worker]
    set timeout [dict get {compose 180000 page 45000 thumbnails 90000 verify 30000 export 45000 source_preview 15000 media_info 10000} [dict get $record operation]]
    set options [dict create timeout_ms $timeout max_bytes 2097152 process_group 1 ui_lifetime 1 label {Scientific print document}]
    if {[catch {set request [scriptJobAsync $command $data [list ::GX::_printDocumentDone $token] $options]} message]} {_printDocumentDone $token [dict create ok 0 error $message];return}
    dict set requests $token request $request
}
proc ::GX::_printDocumentDone {token response} {
    variable ::GX::PrintDocument::requests;variable ::GX::PrintDocument::leases
    if {![dict exists $requests $token]} return
    set record [dict get $requests $token];dict unset requests $token
    set resource [dict get $record resource]
    if {[dict get $record cancelled]} {set response {ok 0 error {Print request cancelled.}}}
    if {[dict get $response ok]} {dict set response result resource_id [dict get $resource id];dict set response result resource_path [dict get $resource path]} elseif {$resource ne {}} {printDocumentRelease [dict get $resource id]}
    set source [dict get $record source_resource]
    if {$source ne {}} {dict incr leases $source -1;_printDocumentRetire $source}
    uplevel #0 [list {*}[dict get $record callback] $response]
}
proc ::GX::printDocumentCancel {token} {
    variable ::GX::PrintDocument::requests
    if {![dict exists $requests $token]} {return 0}
    dict set requests $token cancelled 1
    set request [dict get $requests $token request]
    if {$request ne {}} {scriptJobRequestCancel $request}
    return 1
}
proc ::GX::printDocumentRelease {id} {dict set ::GX::PrintDocument::retired $id 1;_printDocumentRetire $id}
proc ::GX::_printDocumentRetire {id} {
    variable ::GX::PrintDocument::leases;variable ::GX::PrintDocument::retired
    if {![dict exists $retired $id] || [datasetPublicationV2DictDefault $leases $id 0]>0} return
    dict unset retired $id
    resourceManagementAsync release [list resource_id $id state verified_orphan retention_seconds 0] [list ::GX::_printDocumentReleased $id]
}
proc ::GX::_printDocumentReleased {id code result} {if {!$code} {resourceManagementAsync cleanup [list $id] ::GX::_printDocumentCleanupDone}}
proc ::GX::_printDocumentCleanupDone {code result} {if {$code && [llength [info commands ::GX::printDiagnostic]]} {printDiagnostic "Print temporary cleanup: $result"}}

proc ::GX::_printCupsResourceDone {source callback response} {
    dict incr ::GX::PrintDocument::leases $source -1
    _printDocumentRetire $source
    uplevel #0 [list {*}$callback $response]
}

proc ::GX::printDocumentSourcePreview {id callback} {
    set signature [printRecipeSourceSignature graph $id]
    set path [lindex $signature 1]
    # SHA computation is delegated to the worker; stat identity is checked there.
    return [printDocumentRequest source_preview [dict create path $path session $::GX::currentSession stamp [lrange $signature 2 5]] $callback]
}

proc ::GX::printDocumentMediaInfo {id callback} {
    if {[datasetProviderFor $id] eq {remote}} {error {No original remote image transfer is declared.}}
    set path [datasetResolvePath $::GX::currentSession $id]
    set sha [datasetField $id canonical_sha256 [datasetField $id sha256 {}]]
    return [printDocumentRequest media_info [dict create path $path sha256 $sha] $callback]
}
