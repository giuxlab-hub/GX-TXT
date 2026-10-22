# SPDX-License-Identifier: GPL-3.0-or-later
# Printing document authority; existing CORE Dataset/Graph/Preview/Workspace,
# Resource Management and Script Job owners retain their scientific roles.
namespace eval ::GX::PrintDocument {variable cups {};variable ignored 0}
proc ::GX::printRecipeNew {} {
    return [dict create schema gxtxt.print_recipe.v1 title {Scientific print composition} page [dict create paper A4 orientation portrait rows 1 columns 1 margin_mm 12 gap_mm 5 captions 1] items {}]
}
proc ::GX::printRecipePosterNew {} {
    set recipe [printRecipeNew]
    dict set recipe title {Scientific poster}
    dict set recipe page paper A3
    dict set recipe page orientation landscape
    dict set recipe page columns 2
    dict set recipe page layout_mode poster
    dict set recipe page background #ffffff
    return $recipe
}
proc ::GX::printRecipePageSize {page} {
    lassign [dict get {A4 {210 297} A3 {297 420} LETTER {215.9 279.4}} [dict get $page paper]] width height
    if {[dict get $page orientation] eq {landscape}} {return [list $height $width]}
    return [list $width $height]
}
proc ::GX::printRecipeAssetIdentity {item} {
    set identity {}
    foreach key {source_kind source_id source_signature presentation options caption style text} {lappend identity $key [datasetPublicationV2DictDefault $item $key {}]}
    if {[dict exists $item frame]} {lappend identity width_mm [dict get $item frame width_mm] height_mm [dict get $item frame height_mm]}
    return $identity
}
proc ::GX::printRecipeItemLabel {item} {
    set label [string trim [dict get $item caption]]
    if {$label eq {} && [dict get $item source_kind] eq {literal}} {set label [lindex [split [string trim [datasetPublicationV2DictDefault $item text {}]] \n] 0]}
    if {$label eq {}} {set label [dict get {table Table xy Plot image Image pdf {PDF page} text Text metadata Metadata graph Graph annotation Annotation box {Color block} separator Separator} [dict get $item presentation]]}
    if {[string length $label]>100} {set label "[string range $label 0 98]…"}
    return $label
}
proc ::GX::_printRecipeNumber {value minimum maximum label} {
    if {![string is double -strict $value] || [catch {expr {abs($value)<Inf && $value>=$minimum && $value<=$maximum}} valid] || !$valid} {error "$label must be finite, from $minimum to $maximum."}
}
proc ::GX::printRecipeValidate {recipe} {
    foreach key {schema title page items} {if {![dict exists $recipe $key]} {error "Print recipe requires '$key'."}}
    foreach key [dict keys $recipe] {if {$key ni {schema title page items}} {error "Unknown print recipe field '$key'."}}
    if {[dict get $recipe schema] ne {gxtxt.print_recipe.v1} || [string bytelength $recipe]>8388608 || [llength [dict get $recipe items]]>200} {error {Unsupported or oversized print recipe (8 MiB / 200 items).}}
    if {[regexp {[\r\n]} [dict get $recipe title]] || [string length [dict get $recipe title]]>200} {error {Print title must be a single line of at most 200 characters.}}
    set page [dict get $recipe page]
    if {[dict get $page paper] ni {A4 A3 LETTER} || [dict get $page orientation] ni {portrait landscape}} {error {Choose a supported paper size and orientation.}}
    foreach key [dict keys $page] {if {$key ni {paper orientation rows columns margin_mm gap_mm captions layout_mode background}} {error "Unknown print page field '$key'."}}
    set mode [datasetPublicationV2DictDefault $page layout_mode grid]
    if {$mode ni {grid poster}} {error {Choose grid or poster layout.}}
    if {[dict exists $page background] && ![regexp {^#[0-9a-fA-F]{6}$} [dict get $page background]]} {error {Page background must be an RGB color such as #ffffff.}}
    lassign [printRecipePageSize $page] paperWidth paperHeight
    foreach key {rows columns} {if {![string is integer -strict [dict get $page $key]] || [dict get $page $key]<1 || [dict get $page $key]>4} {error {Print grid rows/columns must be from 1 to 4.}}}
    foreach key {margin_mm gap_mm} {set n [dict get $page $key];if {![string is double -strict $n] || [catch {expr {abs($n)<Inf}} finite] || !$finite || $n<0 || $n>60} {error {Print margins and spacing must be finite values from 0 to 60 mm.}}}
    if {![string is boolean -strict [dict get $page captions]]} {error {Print captions must be boolean.}}
    set ids {}
    foreach item [dict get $recipe items] {
        foreach key {id source_kind source_id presentation source_signature options caption} {if {![dict exists $item $key]} {error "Print item requires '$key'."}}
        foreach key [dict keys $item] {if {$key ni {id source_kind source_id presentation source_signature options caption frame style text}} {error "Unknown print item field '$key'."}}
        set id [dict get $item id]
        if {![regexp {^print_[a-zA-Z0-9_]+$} $id] || $id in $ids} {error {Duplicate or invalid print item identity.}}
        lappend ids $id
        if {[dict get $item source_kind] ni {dataset graph literal} || [dict get $item presentation] ni {table xy image pdf text metadata graph annotation box separator}} {error {Unsupported print source or representation.}}
        if {[dict get $item source_kind] eq {literal}} {
            if {$mode ne {poster} || [dict get $item presentation] ni {text annotation box separator} || [dict get $item source_id] ne {} || [dict get $item source_signature] ne {} || ![dict exists $item text] || [string bytelength [dict get $item text]]>1048576 || [dict get $item options] ne {}} {error {Poster authored objects require inert text (at most 1 MiB), empty source identity and empty options.}}
        } elseif {[dict get $item presentation] in {annotation box separator} || [dict exists $item text]} {error {Authored text and shapes must be document-owned literal objects.}}
        if {[dict get $item source_kind] eq {dataset} && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $item source_id]]} {error {Invalid canonical Dataset identity.}}
        if {[regexp {[\r\n]} [dict get $item caption]] || [string length [dict get $item caption]]>400} {error {Print caption must be a single line of at most 400 characters.}}
        set options [dict get $item options]
        foreach key [dict keys $options] {if {$key ni {variables start count x_variable_id y_variable_id pdf_pages}} {error "Unknown print item option '$key'."}}
        foreach key {start count} {if {[dict exists $options $key] && (![string is entier -strict [dict get $options $key]] || [dict get $options $key]<[expr {$key eq {count} ? 1 : 0}] || ($key eq {count} && [dict get $options $key]>10000))} {error {Choose an explicit table range: nonnegative start, count 1–10000.}}}
        if {[dict exists $options variables] && [llength [dict get $options variables]]>64} {error {A print table accepts at most 64 explicitly selected variables.}}
        if {$mode eq {poster} && ![dict exists $item frame]} {error "Poster object $id requires a physical frame."}
        if {[dict exists $item frame]} {
            set frame [dict get $item frame]
            if {[lsort [dict keys $frame]] ne {height_mm page width_mm x_mm y_mm}} {error "Poster object $id requires page, x_mm, y_mm, width_mm and height_mm only."}
            set number [dict get $frame page]
            if {![string is integer -strict $number] || $number<1 || $number>200} {error {Poster page must be from 1 to 200.}}
            foreach key {x_mm y_mm} limit [list $paperWidth $paperHeight] {_printRecipeNumber [dict get $frame $key] 0 $limit "Object $id $key"}
            foreach key {width_mm height_mm} limit [list $paperWidth $paperHeight] {_printRecipeNumber [dict get $frame $key] 1 $limit "Object $id $key"}
            if {[dict get $frame x_mm]+[dict get $frame width_mm]>$paperWidth+1e-7 || [dict get $frame y_mm]+[dict get $frame height_mm]>$paperHeight+1e-7} {error "Poster object $id extends beyond its paper; move or resize it explicitly."}
        }
        if {[dict exists $item style]} {
            dict for {key value} [dict get $item style] {
                switch $key {
                    foreground - background - border {if {![regexp {^#[0-9a-fA-F]{6}$} $value]} {error "Object $id $key requires an RGB color."}}
                    border_pt {_printRecipeNumber $value 0 12 {Border width in points}}
                    padding_mm {_printRecipeNumber $value 0 30 {Object padding in mm}}
                    font_size {_printRecipeNumber $value 6 96 {Font size in points}}
                    weight {if {$value ni {normal bold}} {error {Font weight must be normal or bold.}}}
                    align {if {$value ni {left center right}} {error {Text alignment must be left, center or right.}}}
                    default {error "Unknown poster object style '$key'."}
                }
            }
        }
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
    return [dict create api_id PRINT_DOCUMENT_API_v1 api_version 1 authority services/printing operations {printRecipeNew printRecipePosterNew printRecipePageSize printRecipeAssetIdentity printRecipeItemLabel printRecipeValidate printRecipeHistoryCreate printRecipeHistoryEdit printRecipeDocumentSave printRecipeDocumentRead printRecipeSourceSignature printContentDescribe printDocumentRequest printDocumentCancel printDocumentRelease printDocumentSourcePreview printDocumentMediaInfo printCupsRequest printCupsQuery printCupsCancel printCupsState} transport SCRIPT_JOB_API_v1 cups_lifetime bounded_auxiliary scientific_authority 0 host_operation_contracts [_printDocumentHostContracts]]
}
proc ::GX::_printDocumentHostContracts {} {
    # Curated public host methods only, not arbitrary Tcl procedure discovery.
    # The existing API Browser consumes this documentation without granting
    # Script Bridge/SDK access or invoking printing/resource operations.
    set contracts {}
    foreach {method params resultType resultDescription context} {
        printRecipeNew {} PrintRecipe {New empty A4 portrait Grid recipe; no persistence or preparation.} {No Session required.}
        printRecipePosterNew {} PrintRecipe {New empty A3 landscape two-column Poster recipe.} {No Session required.}
        printRecipePageSize {page PageDictionary {Supported paper and orientation.}} MillimetrePair {Physical width and height in mm after orientation; not complete recipe validation.} {No Session required.}
        printRecipeAssetIdentity {item PrintItem {Recipe source identity, representation, content, style and optional frame.}} ReuseKey {Inert content-reuse key including frame dimensions but not position/page; not a Dataset identity or digest.} {No Session required.}
        printRecipeItemLabel {item PrintItem {Recipe item with caption, source_kind, presentation and optional text.}} String {Readable caption, first literal line or representation name, shortened beyond 100 characters.} {No Session required.}
        printRecipeValidate {recipe PrintRecipe {Inert gxtxt.print_recipe.v1 dictionary; bounded page, items, options, physical frames and styles.}} PrintRecipe {Validated recipe copy or Tcl error; does not resolve scientific sources or persist edits.} {No Session required.}
        printRecipeHistoryCreate {recipe PrintRecipe {Validated initial recipe.}} ScientificHistory {New framework.printing History with initial base, empty steps and cursor zero; not saved.} {Registers the existing Scientific Recipe host.}
        printRecipeHistoryEdit {history ScientificHistory {Existing framework.printing History.} recipe PrintRecipe {Validated new recipe snapshot.} description String {User-visible History step description.}} ScientificHistory {Appended History, branching first when its cursor precedes the end; no persistence.} {Existing Scientific Recipe owner.}
        printRecipeDocumentSave {recipe PrintRecipe {Validated composition recipe.} history ScientificHistory {Validated framework.printing History.} id DocumentID {Empty creates a new document; otherwise updates that current-Session printing document.} expected DocumentStamp {For update, exact generation/revision/SHA list from current metadata; empty cannot authorize an existing-document overwrite.}} DocumentMetadata {Interactive Document metadata including ID, generation, revision and SHA; owner/stamp mismatch raises before update.} {Current Session required; existing Interactive Document authority.}
        printRecipeDocumentRead {id DocumentID {Current-Session printing composition ID.}} InteractiveDocument {Validated framework.printing/print_composition document including payload recipe and History; does not certify a prepared PDF current.} {Current Session and matching document owner/format.}
        printRecipeSourceSignature {kind SourceKind {dataset or graph.} id SourceReference {Canonical Dataset ID, or relative/absolute artwork path under the current Session analysis directory.}} SourceIdentity {Opaque complete scientific/artwork identity including relevant metadata, stat and dependencies; compare unchanged, never manufacture fields.} {Current Session and available original source.}
        printContentDescribe {kind SourceKind {dataset or graph.} id SourceReference {Canonical Dataset ID or current-Session Graph artwork path.}} ContentDescriptor {Actual supported representations, default, reason and source identity; Dataset schema/types/units and row count where available. Not materialization or remote transfer admission.} {Current Session and registered source.}
        printDocumentApiInfo {} APIInfo {API identity, version, 21 legacy operation names, curated host contracts and existing transport/lifetime declarations; no operation execution or access grant.} {No Session required.}
        printDocumentRequest {operation DocumentOperation {compose, page, object_preview, thumbnails, verify, export, source_preview or media_info.} arguments Dictionary {Operation-specific inert arguments documented in PRINT_DOCUMENT_API_v1; optional source_resource leases the supplying managed document.} callback CommandPrefix {Tcl prefix receiving one response dictionary: ok/result or ok/error. Release each successful result resource_id, including obsolete results.}} RequestToken {Asynchronous print-document token, not a completed PDF; resource allocation precedes the managed worker.} {Existing Resource Management and Script Job; derived requests retain frozen PDF/source identities.}
        printDocumentCancel {token RequestToken {Owned print-document token returned by printDocumentRequest.}} Boolean {One marks a live request cancelled, including allocation in flight; zero means unregistered. Completion remains asynchronous.} {Existing request owner; cancellation is not a completion receipt.}
        printDocumentRelease {id ResourceID {Successful response resource_id, not Document/Dataset ID or arbitrary path.}} RetirementRequest {Empty while leases defer retirement; immediate retirement may return an asynchronous resource-request token. Neither result proves cleanup completed.} {Existing active leases outlive their workers; no scientific source deletion.}
        printDocumentSourcePreview {id GraphArtworkPath {Current-Session Graph artwork path, not Dataset ID.} callback CommandPrefix {Prefix receiving the asynchronous ok/result or ok/error response.}} RequestToken {Bounded source_preview request with captured original stat/signature; browsing PNG is not print authority.} {Current Session; original source remains read-only.}
        printDocumentMediaInfo {id DatasetID {Canonical original image Dataset ID; undeclared remote original transfer is rejected.} callback CommandPrefix {Prefix receiving actual decoded dimensions/mode/frame count/printable reason or an error.}} RequestToken {Asynchronous media_info request guarded by recorded source SHA; no scientific publication.} {Current Session and original payload resolution.}
        printCupsRequest {operation CupsOperation {discover, capabilities, submit, job_status or cancel_job.} arguments Dictionary {Operation-specific fields documented in PRINT_DOCUMENT_API_v1; submit requires verified PDF and capabilities. Scientific source guards are rechecked when supplied; Print Studio supplies them. Optional source_resource retains the supplying allocation.} callback CommandPrefix {Prefix receiving the common auxiliary request response.}} AuxiliaryRequestID {Existing Script Job auxiliary request ID with bounded configured timeout; submission response is not physical print completion.} {Configured CUPS metadata; no separate scientific Job registry.}
        printCupsQuery {channel CupsChannel {discovery, capabilities, submission or status.} operation CupsOperation {CUPS operation and arguments obey printCupsRequest.} arguments Dictionary {Inert operation-specific CUPS arguments.} callback CommandPrefix {Prefix receiving only the newest channel generation, added to its response.}} ChannelGeneration {Channel and generation receipt; pending requests coalesce after previous cancellation drains.} {Transient channel state; physical job cancellation uses cancel_job.}
        printCupsCancel {channel CupsChannel {Existing discovery, capabilities, submission or status channel.}} Boolean {Zero for absent channel; otherwise one after generation advance, pending clear and request cancellation. Does not cancel an already accepted physical print job.} {Existing auxiliary channel state.}
        printCupsState {channel CupsChannel {Empty returns all channels and ignored stale-response count; a named channel returns its transient state.}} CupsState {Channel generation, request, pending and last response; operation when established. Not persisted scientific or physical-completion state.} {Read-only transient diagnostics; no CUPS request.}
    } {
        set signature {};set parameters {}
        foreach {name type description} $params {
            if {[info default ::GX::$method $name default]} {lappend signature [list $name $default]} else {lappend signature $name}
            dict set parameters $name [dict create type $type description $description]
        }
        dict set contracts $method [dict create command ::GX::$method arguments $signature parameters $parameters result [dict create type $resultType description $resultDescription] context "Trusted Tcl host only. $context No Script Bridge or C++ SDK grant is implied."]
    }
    return $contracts
}
proc ::GX::printCupsRequest {operation arguments callback} {
    set counts {discover 2 capabilities 2 submit 3 job_status 2 cancel_job 1}
    if {![dict exists $counts $operation]} {error {Unsupported public CUPS operation.}}
    set timeout [configurationGet printing.cups_timeout_ms]
    if {![string is integer -strict $timeout] || $timeout<250 || $timeout>30000} {error {CUPS timeout must be 250–30000 ms.}}
    set source [datasetPublicationV2DictDefault $arguments source_resource {}]
    dict unset arguments source_resource
    set allowed [dict get {discover {} capabilities {printer} submit {printer capability_sha256 pdf pdf_sha256 copies duplex options pages source_manifest} job_status {printer job_id} cancel_job {job_id}} $operation]
    foreach key [dict keys $arguments] {if {$key ni $allowed} {error "Unknown CUPS argument '$key'."}}
    set request [dict merge $arguments [dict create operation $operation timeout_ms $timeout]]
    set options [dict create timeout_ms [expr {$timeout*[dict get $counts $operation]+1500+($operation eq {submit} ? 20000 : 0)}] max_bytes 2097152 process_group 1 ui_lifetime 1 label "CUPS $operation"]
    if {$source ne {}} {dict incr ::GX::PrintDocument::leases $source;set callback [list ::GX::_printCupsResourceDone $source $callback]}
    try {
        return [scriptJobAsync [list [runtimeToolRequired python] -B [file join $::GX::scriptDir services printing gxtxt_print_request.py]] $request $callback $options]
    } on error {message errorOptions} {
        # A refused request never reaches its completion callback. Roll back
        # only this request's lease, preserving other consumers and the error.
        if {$source ne {}} {dict incr ::GX::PrintDocument::leases $source -1;_printDocumentRetire $source}
        return -options $errorOptions $message
    }
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
    # Tk may retain winfo after its application was destroyed. Drain the
    # bookkeeping above, but neither restart work nor call UI code in that case.
    if {[llength [info commands winfo]] && ([catch {winfo exists .} live] || !$live)} {return}
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
    if {$operation ni {compose page object_preview thumbnails verify export source_preview media_info}} {error {Unknown print document operation.}}
    set token print-document#[incr serial]
    set resource [datasetPublicationV2DictDefault $arguments source_resource {}]
    if {$resource ne {}} {dict incr leases $resource}
    dict set requests $token [dict create operation $operation arguments $arguments callback $callback cancelled 0 request {} resource {} source_resource $resource]
    set reservation [dict get {compose 805306368 page 67108864 object_preview 268435456 thumbnails 33554432 source_preview 16777216 media_info 1048576 verify 1048576 export 1048576} $operation]
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
    set timeout [dict get {compose 180000 page 45000 object_preview 45000 thumbnails 90000 verify 30000 export 45000 source_preview 15000 media_info 10000} [dict get $record operation]]
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
