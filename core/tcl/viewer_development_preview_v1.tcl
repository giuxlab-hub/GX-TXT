# SPDX-License-Identifier: GPL-3.0-or-later
# Embedded presentation uses the same admitted distributed C++ worker and
# existing Preview/Document owners. No native library is loaded in Tk.
namespace eval ::GX::PreviewCpp {variable mounts {};variable serial 0;variable replies}
proc ::GX::_previewCppDesign {module root} {
    if {[file normalize [file dirname [moduleField $module descriptor]]] ne [file normalize $root] || [moduleField $module kind {}] ne {preview}} {error {Managed Preview must be normally installed}}
    set design [viewerGuiDesignRead [file join $root gui design.tcldict]]
    if {[dict get $design module_id] ne $module || [dict get $design target] ne {preview} || [dict get $design preview runtime] ne {managed_cpp}} {error {Package is not an admitted managed Preview}}
    if {![llength [dict get $design components]]} {error {Installed managed Preview requires a declared document pane}}
    return $design
}
proc ::GX::viewerDevelopmentPreviewTabs {module root context} {
    set design [_previewCppDesign $module $root]
    if {[_viewerGuiManagedNumericPreview $design]} {return [_previewCppNumericTabs $module $design $context]}
    set id [dict get $context dataset_id]
    set kind [datasetDocumentKind $id]
    if {$kind ni {markdown uml} || ![viewerGuiDocumentCompatible $id $kind]} {return {tabs {}}}
    foreach component [dict get $design components] {if {[dict get $component properties kind] ne $kind} {return {tabs {}}}}
    set description [expr {$kind eq {uml}?[umlDocumentDescribe $id]:[datasetDocumentDescribe $id]}]
    set tabs {}
    foreach component [dict get $design components] {
        set p [dict get $component properties]
        set pane [datasetPublicationV2DictDefault $p pane [expr {$kind eq {uml}?{diagram}:{rendered}}]]
        if {$pane eq {associated_source} && [dict get $description association state] ne {associated}} continue
        lappend tabs [dict create id [dict get $component id] label [datasetPublicationV2DictDefault $p title [string totitle [string map {_ { }} $pane]]] kind gui]
    }
    return [dict create tabs $tabs]
}
proc ::GX::_previewCppReply {variable response} {set $variable $response}
proc ::GX::viewerDevelopmentPreviewMount {module root host context} {
    variable ::GX::PreviewCpp::mounts
    variable ::GX::PreviewCpp::serial
    if {[dict exists $mounts $host] || [dict size $mounts]>=32} {error {Managed Preview lifetime limit reached}}
    set record [_datasetPreviewGuiRequire $host]
    if {[dict get $record module] ne $module || [datasetPreviewGuiContext $host] ne $context} {error {Managed Preview context differs from its actual host}}
    set design [_previewCppDesign $module $root]
    if {[_viewerGuiManagedNumericPreview $design]} {return [_previewCppNumericMount $module $root $host $context $design]}
    set id [dict get $context tab_id];set component {};set ordinal 0
    foreach candidate [dict get $design components] {incr ordinal;if {[dict get $candidate id] eq $id} {set component $candidate;break}}
    if {$component eq {}} {error {Preview tab is not a declared document}}
    set allocation [resourceManagementAllocate compiled_preview_runtime [dict create category temporary lifetime viewer retention_seconds 0]]
    dict set mounts $host [dict create allocation $allocation module $module root $root request {}]
    set request {};set variable ::GX::PreviewCpp::replies(reply[incr serial])
    try {
        set script [file join $::GX::scriptDir core python gxtxt_viewer_development.py]
        set command [list /usr/bin/python3 -I -B $script runtime_inspect $root --runtime-work [dict get $allocation path] --tcl]
        set request [scriptJobAsync $command {} [list ::GX::_previewCppReply $variable] [dict create timeout_ms 30000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled Preview admission}]]
        dict set mounts $host request $request
        vwait $variable
        set reply [set $variable];unset $variable
        if {![dict get $reply ok] || [dict get $reply result status] ne {PASS}} {error {Compiled Preview package admission failed}}
        set admission [dict get $reply result]
        _datasetPreviewGuiRequire $host
        if {[_previewCppDesign $module $root] ne $design} {error {Preview package changed during admission}}
        set command [list /usr/bin/python3 -I -B $script runtime_serve $root --runtime-work [dict get $allocation path]]
        set request [scriptJobAsync $command {} [list ::GX::_previewCppEnded $host] [dict create duplex 1 send_pending_bytes 2097152 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Compiled Preview lifetime}]]
        dict set mounts $host request $request
        set ready [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $request {} 5000]]]
        if {![dict get $ready ok] || [dict get $ready result status] ne {READY}} {error {Compiled Preview worker could not load}}
        set payload [format {{"event":{"kind":0,"component":0,"value":0},"state":%s,"context":{"data":%s,"inputs":[]}}} [viewerDevelopmentStateJson [dict create values [lrepeat 16 0.0] counter 0]] [viewerDevelopmentJsonString $id]]
        set reply [encoding convertfrom utf-8 [binary decode base64 [scriptJobRequestExchange $request $payload]]]
        _datasetPreviewGuiRequire $host
        if {![dict get $reply ok] || [dict get $reply result status] ne {COMPLETED}} {error {Compiled Preview open event failed}}
        set result [dict get $reply result]
        set intents [dict get $result operations]
        if {[llength $intents]!=1} {error {Managed document Preview requires one explicit compiled render intent}}
        set intent [lindex $intents 0]
        if {[dict get $intent operation] ne {document_command} || [dict get $intent component] ne $id || [dict get $intent value] ne {render}} {error {Compiled Preview intent differs from its declared read-only pane}}
        set widget [dict get $record root].document
        set properties [dict get $component properties];set kind [dict get $properties kind]
        set options [dict create mode read_only pane [datasetPublicationV2DictDefault $properties pane [expr {$kind eq {uml}?{diagram}:{rendered}}]] dataset_id [dict get $context dataset_id] toolbar 0]
        if {$kind eq {uml}} {dict set options kind uml;dict set options uml_operations [datasetPublicationV2DictDefault $admission uml_operations {}]}
        set handle [documentEditorMount $widget $options]
        grid $widget -row 0 -column 0 -sticky nsew
        grid rowconfigure [dict get $record root] 0 -weight 1
        dict set mounts $host editor $handle
        dict set mounts $host receipt [dict create source_sha256 [dict get $result source_sha256] binary_sha256 [dict get $ready result binary_sha256] pane_id $id execution compiled_cpp runtime_compilation 0]
        return [dict get $mounts $host receipt]
    } on error {message options} {
        viewerDevelopmentPreviewDispose $host
        return -options $options $message
    }
}
proc ::GX::_previewCppEnded {host response} {
    if {![dict exists $::GX::PreviewCpp::mounts $host]} return
    dict set ::GX::PreviewCpp::mounts $host worker_ended $response
}
proc ::GX::_previewCppReceiptCommitted {id token before after sha} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Preview receipt acknowledgement belongs to CORE}}
    foreach host [dict keys $::GX::PreviewCpp::mounts] {
        set record [dict get $::GX::PreviewCpp::mounts $host]
        if {![dict exists $record editor]} continue
        if {[catch {set current [_datasetPreviewGuiRequire $host]}] || [dict get $current dataset] ne $id} continue
        _documentEditorPreviewReceiptCommitted [dict get $record editor] $id $token $before $after $sha
    }
}
proc ::GX::viewerDevelopmentPreviewDispose {host} {
    variable ::GX::PreviewCpp::mounts
    if {![dict exists $mounts $host]} return
    set record [dict get $mounts $host];dict unset mounts $host
    if {[dict exists $record editor]} {catch {documentEditorCommand [dict get $record editor] dispose}}
    set request [dict get $record request]
    if {$request ne {}} {scriptJobRequestCancel $request closed}
    resourceManagementRelease [dict get $record allocation id] retained_diagnostic 3600
}
source [file join [file dirname [info script]] viewer_development_preview_numeric_v1.tcl]
