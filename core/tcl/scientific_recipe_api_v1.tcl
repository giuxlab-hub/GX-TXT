# SPDX-License-Identifier: GPL-3.0-or-later
# Declarative recipes contain logical identities and owned scientific resources.
# Nothing in a recipe is evaluated as Tcl or interpreted as a filesystem path.
namespace eval ::GX::ScientificRecipe {variable hosts {}}
proc ::GX::scientificRecipeApiInfo {} {
    return [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 operations {inspect validate geometry_state proposal export_python rebase data_decode} host_operations {scientificHistoryCreate scientificHistoryValidate scientificHistoryState scientificHistoryAppend scientificHistoryNavigate scientificHistoryBranch scientificHistoryContextAttach scientificHistoryContextClose scientificHistoryContextSetParent scientificHistoryViewerSeek scientificHistoryViewerDetach scientificHistoryViewerDiscard scientificHistoryViewerReset scientificHistoryViewerAttach scientificHistoryViewerRecord scientificHistoryViewerState scientificHistoryViewerStateAt scientificHistoryViewerOperation scientificHistoryViewerAuxiliary scientificHistoryViewerContextAction scientificHistoryViewerEditable scientificHistoryViewerPrepareEdit scientificHistoryViewerChanged scientificHistoryViewerRecordOperation scientificHistoryViewerSubmitPatch scientificHistoryDrafts scientificHistoryFailureRecord scientificHistoryViewerSummary scientificHistoryViewerRestoreContext scientificHistoryViewerGroupExpand scientificHistoryViewerStatus scientificHistoryViewerFlush scientificHistoryViewerBindDocument scientificHistoryViewerRequest scientificHistoryHookComplete scientificHistoryHookCancel scientificHistoryPopup scientificHistoryViewerNavigate scientificHistoryViewerBrowse scientificHistoryViewerClear scientificHistoryStripFields scientificHistoryStripValidate scientificHistoryViewerStripGet scientificHistoryViewerStripSet scientificHistoryViewerStripToggle scientificHistoryViewerStrip scientificHistoryGroupedEntries scientificHistoryViewerDetails scientificHistoryViewerRefresh} format gxtxt.scientific_recipe.v1 maximum_bytes 8388608 maximum_steps 4096 implicit_publication 0]
}
proc ::GX::scientificRecipeHostRegister {owner callbacks} {
    foreach key {capture validate replay} {if {![dict exists $callbacks $key]} {error "Recipe host requires $key"}}
    dict set ::GX::ScientificRecipe::hosts $owner $callbacks
}
proc ::GX::scientificRecipeDataDecode {encoded expectedFormat} {
    if {![regexp {^gxtxt\.[a-z0-9_.]+\.v[1-9][0-9]*$} $expectedFormat]} {error {Invalid versioned scientific recipe format}}
    if {[string length $encoded]>11190272} {error "Scientific recipe exceeds the 8 MiB limit"}
    if {[catch {encoding convertfrom utf-8 [binary decode base64 -strict $encoded]} recipe]||[catch {dict size $recipe}]} {error "Malformed inert scientific recipe"}
    set maximum [expr {[datasetPublicationV2DictDefault $recipe legacy_import 0] && $expectedFormat eq {gxtxt.scientific_recipe.v1} ? 8392704 : 8388608}]
    if {[string bytelength $recipe]>$maximum||![dict exists $recipe format]||[dict get $recipe format] ne $expectedFormat} {error {Scientific recipe format or size differs from its declared contract}}
    return $recipe
}
proc ::GX::scientificRecipeDecode {encoded} {
    set recipe [scientificRecipeDataDecode $encoded gxtxt.scientific_recipe.v1]
    foreach key {format workbench_id required_apis plugin_versions base steps sources} {if {![dict exists $recipe $key]} {error "Recipe requires $key"}}
    if {[dict get $recipe format] ne "gxtxt.scientific_recipe.v1"||[llength [dict get $recipe steps]]>4096} {error "Unsupported scientific recipe format or step count"}
    _interactiveDocumentValidateOwner [dict get $recipe workbench_id] scientific_recipe
    return $recipe
}
proc ::GX::scientificRecipeEncode {recipe} {
    set maximum [expr {[datasetPublicationV2DictDefault $recipe legacy_import 0] ? 8392704 : 8388608}]
    if {[string bytelength $recipe]>$maximum} {error "Scientific recipe exceeds the 8 MiB limit; start a new recording"}
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $recipe]]
}
proc ::GX::scientificRecipeInspect {encoded} {
    set recipe [scientificRecipeDecode $encoded]
    return [dict create format [dict get $recipe format] workbench_id [dict get $recipe workbench_id] step_count [llength [dict get $recipe steps]] required_apis [dict get $recipe required_apis] source_count [llength [dict get $recipe sources]]]
}
proc ::GX::scientificRecipeValidate {encoded} {
    set recipe [scientificRecipeDecode $encoded];set owner [dict get $recipe workbench_id]
    foreach step [dict get $recipe steps] {
        foreach key {api_id api_version operation parameters targets result_ids working_unit patch} {if {![dict exists $step $key]} {error "Recipe semantic step requires $key"}}
        if {[dict get $step api_version]!=1||[dict get $step api_id] ni {SCIENTIFIC_RECIPE_API_v1 NATIVE_2D_GEOMETRY_API_v1 NATIVE_3D_GEOMETRY_API_v1}} {error "Unsupported recipe operation API/version"}
        workbenchExtensionRequireApi [dict get $step api_id]
    }
    foreach api [dict get $recipe required_apis] {workbenchExtensionRequireApi $api}
    dict for {module version} [dict get $recipe plugin_versions] {
        if {![moduleIsEnabled $module]||[moduleField $module version {}] ne $version} {error "Recipe requires enabled plugin $module version $version"}
    }
    foreach source [dict get $recipe sources] {
        if {[datasetPublicationV2DictDefault $source source_kind curve_source] eq "geometry_dataset"} {
            set id [dict get $source dataset_id]
            if {[dict get [sessionInspectionDatasetPayload $id] sha256] ne [dict get $source fingerprint]} {error "Recipe source Dataset fingerprint changed: $id"}
            continue
        }
        set token [curveSourceOpen $::GX::currentSession [dict get $source request]]
        try {if {[dict get [curveSourceDescribe $token] source_id] ne [dict get $source fingerprint]} {error "Recipe source Dataset fingerprint changed: [dict get $source request dataset_id]"}} finally {curveSourceClose $token}
    }
    if {![dict exists $::GX::ScientificRecipe::hosts $owner]} {
        # Activate the public owner API in script executions as well as GUI hosts.
        foreach api [modulePublicApiIds $owner] {modulePublicApiActivate $owner $api}
    }
    if {![dict exists $::GX::ScientificRecipe::hosts $owner]} {error "Recipe owner has no public replay adapter"}
    set callbacks [dict get $::GX::ScientificRecipe::hosts $owner]
    uplevel #0 [list {*}[dict get $callbacks validate] $recipe]
    return [dict merge [scientificRecipeInspect $encoded] [dict create status validated]]
}
proc ::GX::scientificRecipeProposal {encoded} {
    scientificRecipeValidate $encoded
    return [dict create status ok operations [list [dict create operation replay_recipe encoded $encoded]] warnings {} provenance [dict create api_id SCIENTIFIC_RECIPE_API_v1 api_version 1 replay_policy validated_logical_geometry_operations]]
}
proc ::GX::scientificRecipeGeometryState {encoded {stepCount -1}} {
    scientificRecipeValidate $encoded;set recipe [scientificRecipeDecode $encoded];set steps [dict get $recipe steps]
    if {![string is entier -strict $stepCount]||$stepCount< -1||$stepCount>[llength $steps]} {error "Invalid recipe semantic step count"}
    if {$stepCount<0} {set stepCount [llength $steps]}
    set state [dict get $recipe base]
    foreach step [lrange $steps 0 [expr {$stepCount-1}]] {if {$stepCount==0} break;set state [scientificRecipeApplyPatch $state [dict get $step patch]]}
    return $state
}
proc ::GX::scientificRecipeReplay {owner context encoded} {
    set recipe [scientificRecipeDecode $encoded]
    if {[dict get $recipe workbench_id] ne $owner} {error "Recipe belongs to a different Workbench"}
    scientificRecipeValidate $encoded
    return [uplevel #0 [list {*}[dict get $::GX::ScientificRecipe::hosts $owner replay] $context $recipe]]
}
proc ::GX::scientificRecipeCapture {owner context} {
    if {![dict exists $::GX::ScientificRecipe::hosts $owner]} {error "Recipe owner is unavailable"}
    set recipe [uplevel #0 [list {*}[dict get $::GX::ScientificRecipe::hosts $owner capture] $context]]
    set encoded [scientificRecipeEncode $recipe];scientificRecipeValidate $encoded
    return $encoded
}
proc ::GX::scientificRecipeExportPython {encoded destination} {
    scientificRecipeValidate $encoded
    set script "# GX-TXT scientific recipe; public APIs and stable logical identities.\nfrom gxtxt import gxtxt_api_call\nRECIPE = '$encoded'\nproposal = gxtxt_api_call('SCIENTIFIC_RECIPE_API_v1', 'proposal', \[RECIPE\])\ngxtxt_api_call('WORKBENCH_EXTENSION_API_v1', 'return_result', \[proposal\])\n"
    return [filePublicationPublishBundle [list [dict create id recipe destination $destination writer [list ::GX::_scientificRecipeWrite $script]]]]
}
proc ::GX::_scientificRecipeWrite {text channel context} {puts -nonewline $channel $text}
proc ::GX::scientificRecipeApplyPatch {state patch} {
    dict for {id record} $patch {if {$record eq "@gxtxt.recipe.delete"} {if {[dict exists $state $id]} {dict unset state $id}} else {dict set state $id $record}}
    return $state
}
proc ::GX::scientificRecipeAppend {record before after semantic} {
    if {$record eq {}} {set record [dict create base $before steps {}]}
    set patch {};dict for {id value} $after {if {![dict exists $before $id]||[dict get $before $id] ne $value} {dict set patch $id $value}}
    foreach id [dict keys $before] {if {![dict exists $after $id]} {dict set patch $id @gxtxt.recipe.delete}}
    if {$patch eq {}} {return $record}
    dict set semantic patch $patch
    dict lappend record steps $semantic
    if {[datasetPublicationV2DictDefault $record retention legacy] eq "complete"} {
        if {[llength [dict get $record steps]]>4096} {error {History limit reached (4096 steps). Export/save this Workspace and deliberately start a new recording before further edits.}}
        scientificRecipeEncode $record
        return $record
    }
    if {[llength [dict get $record steps]]>128} {
        set oldest [lindex [dict get $record steps] 0]
        dict set record base [scientificRecipeApplyPatch [dict get $record base] [dict get $oldest patch]]
        dict set record steps [lrange [dict get $record steps] 1 end]
        dict set record rebased 1
    }
    # Bound encoded history by advancing the base checkpoint, never by dropping
    # the current scientific state or turning ordinary editing into an error.
    while {[string bytelength $record]>8388608&&[llength [dict get $record steps]]>0} {
        set oldest [lindex [dict get $record steps] 0]
        dict set record base [scientificRecipeApplyPatch [dict get $record base] [dict get $oldest patch]]
        dict set record steps [lrange [dict get $record steps] 1 end];dict set record rebased 1
    }
    scientificRecipeEncode $record
    return $record
}

# Explicit owner-neutral history reset. This pure operation returns a candidate;
# Document/Recovery services remain responsible for the durable transaction.
proc ::GX::scientificRecipeRebase {record current context} {
    foreach key {owner document_id retention} {if {![dict exists $context $key]} {error "History rebase requires $key"}}
    set owner [dict get $context owner]
    if {![dict exists $::GX::ScientificRecipe::hosts $owner]} {error {History owner has no registered scientific state validator}}
    if {[dict get $context retention] ni {complete rolling}} {error {Invalid history retention policy}}
    if {[catch {dict size $current}] || [catch {dict size $record}]} {error {History and current state must be inert dictionaries}}
    if {$record eq {}} {set record [dict create base $current steps {}]}
    foreach key {base steps} {if {![dict exists $record $key]} {error "History requires $key"}}
    if {[llength [dict get $record steps]]>4096} {error {Invalid retained history step count}}
    foreach {field expected} [list workbench_id $owner document_id [dict get $context document_id]] {
        if {[dict exists $record $field] && [dict get $record $field] ne $expected} {error "History $field does not match the requested owner"}
    }
    scientificRecipeEncode $record
    set candidate [dict replace $record base $current steps {}]
    if {[dict exists $candidate cursor]} {dict set candidate cursor 0}
    dict set candidate retention [dict get $context retention]
    # Internal retained history can be embedded in a portable Workspace. Do
    # not introduce a document binding into records that never had one; full
    # exported recipes retain and validate their existing binding above.
    dict set candidate history_reset [dict create discarded_steps [llength [dict get $record steps]] policy explicit_current_checkpoint]
    scientificRecipeEncode $candidate
    uplevel #0 [list {*}[dict get $::GX::ScientificRecipe::hosts $owner validate] $candidate]
    return $candidate
}
source [file join [file dirname [info script]] scientific_recipe_history.tcl]
