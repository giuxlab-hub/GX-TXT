# SPDX-License-Identifier: GPL-3.0-or-later
# A workspace is an Interactive Document with provider metadata, not a second
# registry. Its ID, generation, transaction and resource lifetime remain CORE's.
namespace eval ::GX::SessionWorkspace {variable providers {};variable views {};variable refreshTimer {}}
proc ::GX::sessionWorkspaceApiInfo {} {
    return [dict create api_id SESSION_WORKSPACE_API_v1 api_version 1 operations {list get create update rename delete validate note_read note_write preview_set export import} managed_destinations 1]
}
proc ::GX::sessionWorkspaceProviderRegister {provider descriptor} {
    variable ::GX::SessionWorkspace::providers
    foreach field {module_id type schema version validate open} {if {![dict exists $descriptor $field]} {error "Workspace provider needs $field"}}
    _interactiveDocumentValidateOwner [dict get $descriptor module_id] $provider
    dict set providers $provider $descriptor
}
proc ::GX::sessionWorkspaceProviderDiscover {module} {
    set data $::GX::moduleCatalog($module,dict)
    foreach provider [splitList [descriptorValue $data workspaces ids {}]] {
        set section workspace.$provider
        set entry [descriptorValue $data $section entrypoint {}]
        set root [file normalize [file dirname [moduleField $module descriptor]]]
        set file [file normalize [file join $root $entry]]
        if {$entry eq {} || ![string match ${root}/* $file] || ![file isfile $file]} {error {Invalid Workspace provider contribution}}
        source $file
        set descriptor [dict create module_id $module]
        foreach field {type schema version validate open} {dict set descriptor $field [descriptorValue $data $section $field {}]}
        set versions [descriptorValue $data $section accepted_versions {}]
        if {$versions ne {}} {dict set descriptor accepted_versions [splitList $versions]}
        sessionWorkspaceProviderRegister $provider $descriptor
    }
}
proc ::GX::_workspaceProvider {provider} {
    variable ::GX::SessionWorkspace::providers
    if {![dict exists $providers $provider]} {error "Workspace provider '$provider' is unavailable"}
    set descriptor [dict get $providers $provider]
    set module [dict get $descriptor module_id]
    if {[moduleField $module descriptor {}] eq {} || ![moduleIsEnabled $module]} {error "Workspace provider '$provider' is not installed or enabled"}
    return $descriptor
}
proc ::GX::_workspaceValidatePayload {provider payload version {deep 0}} {
    set descriptor [_workspaceProvider $provider]
    if {$version ni [datasetPublicationV2DictDefault $descriptor accepted_versions [list [dict get $descriptor version]]]} {error "Unsupported workspace schema version '$version'"}
    if {[string bytelength $payload]>16777216} {error {Workspace payload exceeds 16 MiB; use managed resources for large scientific values}}
    if {[catch {dict size $payload}]} {error {Workspace payload must be a dictionary}}
    uplevel #0 [list {*}[dict get $descriptor validate] $payload]
    if {$deep&&[dict exists $descriptor validate_deep]} {uplevel #0 [list {*}[dict get $descriptor validate_deep] $payload]}
}
proc ::GX::sessionWorkspaceList {} {
    variable currentSession
    if {$currentSession eq {}||![file isdirectory $currentSession]} {return {}}
    variable ::GX::SessionWorkspace::providers
    set result {}
    foreach doc [interactiveDocumentList] {
        set provider [dict get $doc provider_id]
        if {![dict exists $providers $provider]||[dict get $doc format] ne [dict get $providers $provider schema] || [catch {_workspaceProvider $provider}]} continue
        lappend result [dict remove [sessionWorkspaceGet [dict get $doc id]] payload]
    }
    return $result
}
proc ::GX::sessionWorkspaceGet {id} {
    set doc [interactiveDocumentRead $id];set provider [dict get $doc provider_id]
    set descriptor [_workspaceProvider $provider]
    if {[dict get $doc format] ne [dict get $descriptor schema]} {error {Document is not a registered workspace}}
    set payload [dict get $doc payload]
    set metadata [datasetPublicationV2DictDefault $payload workspace_metadata [dict create name "[dict get $descriptor type] $id" preview {} note {}]]
    return [dict merge [dict remove $doc payload] [dict create workspace_id $id name [dict get $metadata name] type [dict get $descriptor type] schema [dict get $doc format] schema_version [dict get $doc format_version] preview [dict get $metadata preview] note [dict get $metadata note] payload [dict remove $payload workspace_metadata]]]
}
proc ::GX::_workspaceName {name {except {}}} {
    set name [string trim $name];_interactiveDocumentValidateSingleLine $name {Workspace name}
    if {$name eq {}||[string length $name]>160} {error {Workspace name must contain 1..160 characters}}
    foreach item [sessionWorkspaceList] {if {[dict get $item workspace_id] ne $except&&[dict get $item name] eq $name} {error "Workspace name '$name' already exists"}}
    return $name
}
proc ::GX::sessionWorkspaceCreate {provider name payload} {
    set descriptor [_workspaceProvider $provider];set version [dict get $descriptor version]
    set name [_workspaceName $name];_workspaceValidatePayload $provider $payload $version 1
    _workspacePreflightResources $payload
    dict set payload workspace_metadata [dict create name $name preview {} note {}]
    set doc [interactiveDocumentCreate [dict get $descriptor module_id] $provider [dict get $descriptor schema] $version $payload]
    return [sessionWorkspaceGet [dict get $doc id]]
}
proc ::GX::sessionWorkspaceUpdate {id payload} {
    set workspace [sessionWorkspaceGet $id]
    _workspaceValidatePayload [dict get $workspace provider_id] $payload [dict get $workspace schema_version] 1
    set prior [dict get [interactiveDocumentRead $id] payload]
    _workspacePreflightResources $payload $prior
    set metadata [dict get $prior workspace_metadata]
    dict set payload workspace_metadata $metadata
    interactiveDocumentUpdate $id $payload
    return [sessionWorkspaceGet $id]
}
proc ::GX::sessionWorkspacePromote {id {name {}}} {
    set workspace [sessionWorkspaceGet $id]
    set doc [interactiveDocumentRead $id];set payload [dict get $doc payload]
    if {![dict exists $payload workspace_metadata]} {
        if {$name eq {}} {set name [dict get $workspace name]}
        dict set payload workspace_metadata [dict create name [_workspaceName $name $id] preview {} note {}]
        interactiveDocumentUpdate $id $payload
    }
    return [sessionWorkspaceGet $id]
}
proc ::GX::sessionWorkspaceRename {id name} {
    sessionWorkspacePromote $id
    set payload [dict get [interactiveDocumentRead $id] payload]
    dict set payload workspace_metadata name [_workspaceName $name $id]
    interactiveDocumentUpdate $id $payload
    return [sessionWorkspaceGet $id]
}
proc ::GX::sessionWorkspaceDelete {id} {
    sessionWorkspaceGet $id
    set path [_noteDocumentPath $id]
    interactiveDocumentDelete $id
    if {[file exists $path]} {file delete -- $path}
    return 1
}
proc ::GX::sessionWorkspaceValidate {id} {
    set workspace [sessionWorkspaceGet $id]
    _workspaceValidatePayload [dict get $workspace provider_id] [dict get $workspace payload] [dict get $workspace schema_version] 1
    set references {};set budget 0
    _documentResourceReferences [dict get [interactiveDocumentRead $id] payload] $id 0 budget references
    if {[dict get $workspace note] ne {}} {noteDocumentRead $id}
    return [dict create valid 1 resource_count [dict size $references] workspace_id $id]
}
proc ::GX::managedResourceWrite {document metadata bytes} {
    set writer [interactiveDocumentResourceOpenWriter $document $metadata]
    try {
        for {set i 0} {$i<[string length $bytes]} {incr i 1048576} {interactiveDocumentResourceAppend $writer [string range $bytes $i [expr {$i+1048575}]]}
        set resource [interactiveDocumentResourceFinalize $writer];set writer {}
        return $resource
    } finally {if {$writer ne {}} {interactiveDocumentResourceAbort $writer}}
}
proc ::GX::sessionWorkspacePreviewSet {id reference} {
    sessionWorkspacePromote $id
    interactiveDocumentResourceInfo $reference
    if {[dict get $reference document_id] ne $id||[dict get $reference metadata format] ni {image.png image.svg}} {error {Preview must be an image owned by this workspace}}
    set payload [dict get [interactiveDocumentRead $id] payload]
    dict set payload workspace_metadata preview $reference
    interactiveDocumentUpdate $id $payload
    return [sessionWorkspaceGet $id]
}
proc ::GX::_noteDocumentPath {id} {sessionWorkspaceGet $id;return [_noteDocumentManagedPath $id]}
proc ::GX::_noteDocumentManagedPath {id} {
    if {![interactiveDocumentExists $id]} {error {Note owner does not exist}}
    set session [_interactiveDocumentRequireSession];set path $session
    foreach part [list notes workspaces "$id.md"] {
        set path [file join $path $part]
        if {![catch {file lstat $path status}]&&$status(type) eq "link"} {error {Note document symlinks are forbidden}}
    }
    return $path
}
proc ::GX::noteDocumentRead {id} {
    set path [_noteDocumentPath $id]
    set workspace [sessionWorkspaceGet $id];set association [dict get $workspace note]
    if {$association ne {}&&(![file isfile $path]||[sha256File $path] ne [dict get $association sha256])} {error {Workspace note is missing or corrupt}}
    return [dict create workspace_id $id text [noteReadUtf8 $path] format GX-Markup]
}
proc ::GX::noteDocumentWrite {id text} {
    if {[string length [encoding convertto utf-8 $text]]>1048576} {error {Note source exceeds 1 MiB}}
    sessionWorkspacePromote $id
    set path [_noteDocumentPath $id];set existed [file exists $path];set before [noteReadUtf8 $path]
    try {
        noteWriteUtf8 $path $text
        set payload [dict get [interactiveDocumentRead $id] payload]
        dict set payload workspace_metadata note [dict create api_id NOTE_DOCUMENT_API_v1 workspace_id $id sha256 [sha256File $path]]
        interactiveDocumentUpdate $id $payload
    } on error {message options} {
        if {$existed} {noteWriteUtf8 $path $before} elseif {[file exists $path]} {file delete -- $path}
        return -options $options $message
    }
    return [noteDocumentRead $id]
}
proc ::GX::noteDocumentOpen {id {mode view}} {
    set workspace [sessionWorkspaceGet $id];set text [dict get [noteDocumentRead $id] text]
    if {$mode eq "edit"} {return [openMarkupEditor "Notes — [dict get $workspace name]" $text [list ::GX::noteDocumentWrite $id]]}
    if {$mode ne "view"} {error {Note mode must be view or edit}}
    set window .workspaceNoteView;catch {destroy $window};toplevel $window;wm title $window "Notes — [dict get $workspace name]"
    text $window.text -wrap word -width 80 -height 25;pack $window.text -fill both -expand 1
    markupConfigurePreviewTags $window.text;markupRenderStringToWidget $window.text $text;$window.text configure -state disabled
    ttk::button $window.edit -text Edit -command [list ::GX::noteDocumentOpen $id edit];pack $window.edit -side bottom
    return $window
}
proc ::GX::sessionWorkspaceOpen {id} {
    set workspace [sessionWorkspaceGet $id];sessionWorkspaceValidate $id
    set descriptor [_workspaceProvider [dict get $workspace provider_id]]
    set module [dict get $descriptor module_id]
    foreach api [modulePublicApiIds $module] {modulePublicApiActivate $module $api}
    set context [parameterContext [dict get [_datasetPrivateModuleContext $module] capability] $id]
    parameterList $context
    return [_datasetPrivateWithModule $module [list {*}[dict get $descriptor open] $id]]
}
proc ::GX::_workspaceCurveValidate {payload} {
    foreach key {version curves next active view reference target external_feedback} {if {![dict exists $payload $key]} {error "Curve workspace is missing $key"}}
    if {[dict get $payload version]!=2||![string is entier -strict [dict get $payload next]]||[dict get $payload next]<0||[catch {dict size [dict get $payload curves]}]} {error {Unsupported Curve workspace payload}}
}
proc ::GX::_workspaceCurveValidateDeep {payload} {
    native2DEnsure;set scene [::GX::Native2D::core scene]
    try {
        ::GX::Native2D::core view $scene [dict get $payload view]
        dict for {id record} [dict get $payload curves] {
            foreach key {id name source samples x y parents operations representation visible locked edited breaks} {if {![dict exists $record $key]} {error "Curve $id is missing $key"}}
            if {[dict get $record id] ne $id} {error {Curve identity mismatch}}
            if {[dict exists $record working_unit]&&[dict get $record working_unit] ne {}} {unitRegistryConversionPlan [dict get $record working_unit] [dict get $record working_unit]}
            if {[datasetPublicationV2DictDefault $record dataset_binding_only 0]} {
                if {[dict get $record source] eq {}||[dict get $record edited]||[dict get $record samples] ne {}||[dict exists $record sketch_definition]||[dict exists $record geometry_resource]} {error {Dataset binding cannot contain a second geometry authority}}
                foreach key {source_request source_descriptor point_count} {if {![dict exists $record $key]} {error "Dataset binding is missing $key"}}
                foreach key {dataset_id x_variable_id y_variable_id} {if {![dict exists $record source_request $key]} {error "Dataset request is missing $key"}}
                if {[dict get $record source_request dataset_id] ne [dict get $record source]} {error {Dataset source binding identity mismatch}}
                if {![string is entier -strict [dict get $record point_count]]||[dict get $record point_count]<1} {error {Dataset binding requires a positive authoritative point count}}
            } elseif {[dict exists $record sketch_definition]} {
                set object [::GX::Native2D::core sketch_create $scene [dict get $record sketch_definition] 2]
                ::GX::Native2D::core delete $scene $object
            } elseif {[dict exists $record geometry_resource]} {
                set resource [dict get $record geometry_resource]
                set count [dict get $resource metadata point_count]
                if {![string is entier -strict $count]||$count<1||[dict get $resource metadata format] ne "native2d.float64_xy_le_v1"||[dict get $resource size_bytes]!=16*$count} {error {Invalid retained geometry resource shape}}
            } else {
                set points {};foreach sample [dict get $record samples] {lappend points [list [dict get $sample x] [dict get $sample y]]}
                if {$points eq {}} {error {Curve has no retained geometry or samples}}
                set object [::GX::Native2D::core add $scene $points];::GX::Native2D::core delete $scene $object
            }
        }
        if {[dict exists $payload cad_workspace reference_images]} {
            dict for {id record} [dict get $payload cad_workspace reference_images] {
                unitRegistryConversionPlan [dict get $record state length_unit] m
                lassign [_native2DImageDimensions [dict get $record resource]] width height
                if {$width!=[dict get $record state width]||$height!=[dict get $record state height]} {error {Raster dimensions differ from retained image state}}
                set object [::GX::Native2D::core image_create $scene [dict get $record state]]
                if {[dict get $record state resource_id] ne [dict get $record resource sha256]} {error {Raster resource identity mismatch}}
                ::GX::Native2D::core delete $scene $object
            }
        }
    } finally {::GX::Native2D::core destroy $scene}
}
proc ::GX::_workspaceCurveOpen {id} {
    modulePublicApiActivate viewer.curve_workbench CURVE_WORKBENCH_API_v1
    return [::GX::CurveWorkbench::open [dict create workspace_id $id]]
}
::GX::sessionWorkspaceProviderRegister curve_workbench [dict create module_id viewer.curve_workbench type {Curve Workbench} schema gxtxt.curve_workbench.workspace version 2.0 validate ::GX::_workspaceCurveValidate validate_deep ::GX::_workspaceCurveValidateDeep open ::GX::_workspaceCurveOpen]
# Export packages use the existing Portable Resource manifest and integrity
# checks. Script outputs land in the same Document-owned writer authority.
proc ::GX::sessionWorkspaceExport {id} {
    variable scriptDir;variable version
    sessionWorkspacePromote $id;sessionWorkspaceValidate $id
    set workspace [sessionWorkspaceGet $id];set doc [interactiveDocumentRead $id]
    set root [_documentResourceRoot $id];file mkdir $root
    set channel [file tempfile plan [file join $root .export-plan-]]
    set archive "${plan}.zip"
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        foreach {key value} [list workspace_id $id name [dict get $workspace name] provider_id [dict get $workspace provider_id] module_id [dict get $workspace module_id] schema [dict get $workspace schema] schema_version [dict get $workspace schema_version] payload [dict get $doc payload]] {puts $channel "$key\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]"}
        set references {};_workspacePackageReferences [dict get $doc payload] 0 references
        dict for {sha reference} $references {
            interactiveDocumentResourceInfo $reference
            puts $channel "blob\t$sha\t[binary encode base64 -maxlen 0 [dict get $reference document_id]]"
        }
        close $channel;set channel {}
        _portableResourceRun export-workspace [_interactiveDocumentRequireSession] $plan $archive $version
        return [interactiveDocumentResourceImportNumeric $id $archive {format gxtxt.workspace.zip}]
    } finally {if {$channel ne {}} {close $channel};file delete -force -- $plan $archive}
}
proc ::GX::_workspaceRemapResources {value mapping depth} {
    if {$depth>64} {error {Workspace resource nesting exceeds limit}}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        set sha [dict get $value sha256]
        if {![dict exists $mapping $sha]} {error {Workspace references an unpackaged resource}}
        return [dict merge [dict get $mapping $sha] [dict create metadata [_workspaceRemapResources [dict get $value metadata] $mapping [expr {$depth+1}]]]]
    }
    if {[catch {llength $value} n]||$n==0} {return $value}
    set result {};foreach item $value {if {$item eq $value} {return $value};lappend result [_workspaceRemapResources $item $mapping [expr {$depth+1}]]}
    return $result
}
proc ::GX::sessionWorkspaceImport {resource {name {}}} {
    interactiveDocumentResourceInfo $resource
    if {[dict get $resource metadata format] ne "gxtxt.workspace.zip"} {error {Import requires a managed Workspace package resource}}
    set path [file join [_documentResourceRoot [dict get $resource document_id]] [dict get $resource sha256].blob]
    return [_sessionWorkspaceImportPath $path $name]
}
proc ::GX::_sessionWorkspaceImportPath {path {name {}}} {
    set session [_interactiveDocumentRequireSession]
    set stage [file join $session metadata .workspace-import-[pid]-[clock clicks]]
    set created {}
    try {
        _portableResourceRun extract $path $stage
        set fields [_portableResourceFields [file join $stage workspace identity.json]]
        set provider [dict get $fields provider_id];set descriptor [_workspaceProvider $provider]
        if {[dict get $fields schema] ne [dict get $descriptor schema]||[dict get $fields module_id] ne [dict get $descriptor module_id]} {error {Workspace provider/schema mismatch}}
        set payload [noteReadUtf8 [file join $stage workspace payload.utf8]]
        _workspaceValidatePayload $provider $payload [dict get $fields schema_version]
        if {$name eq {}} {set name [dict get $fields name]}
        set name [_workspaceName $name]
        # Preflight every embedded reference before allocating a Document. The
        # created Document is removed on failure; no partial workspace survives.
        set old [dict get $payload workspace_metadata];set references {};set budget 0
        _workspacePackageReferences $payload 0 references
        dict for {sha ref} $references {
            set blob [file join $stage workspace blobs $sha.blob]
            if {![file isfile $blob]||[file size $blob]!=[dict get $ref size_bytes]||[sha256File $blob] ne $sha} {error {Packaged workspace resource is missing or corrupt}}
        }
        set note [file join $stage workspace notes.md]
        if {[dict get $old note] ne {}&&(![file isfile $note]||[sha256File $note] ne [dict get $old note sha256])} {error {Packaged note is missing or corrupt}}
        set receipt [interactiveDocumentCreate [dict get $descriptor module_id] $provider gxtxt.workspace.staging [dict get $descriptor version] {}];set created [dict get $receipt id]
        set mapping {}
        dict for {sha ref} $references {dict set mapping $sha [interactiveDocumentResourceImportNumeric $created [file join $stage workspace blobs $sha.blob] [dict get $ref metadata]]}
        set payload [_workspaceRemapResources $payload $mapping 0]
        dict set payload workspace_metadata name $name
        dict set payload workspace_metadata note {}
        if {[dict get $old note] ne {}} {
            set managedNote [_noteDocumentManagedPath $created]
            noteWriteUtf8 $managedNote [noteReadUtf8 $note]
            dict set payload workspace_metadata note [dict create api_id NOTE_DOCUMENT_API_v1 workspace_id $created sha256 [sha256File $managedNote]]
        }
        _workspaceValidatePayload $provider $payload [dict get $descriptor version] 1
        interactiveDocumentUpdate $created $payload [dict get $descriptor schema] [dict get $descriptor version]
        sessionWorkspaceValidate $created
        return [sessionWorkspaceGet $created]
    } on error {message options} {
        if {$created ne {}&&[interactiveDocumentExists $created]} {interactiveDocumentDelete $created;set note [file join $session notes workspaces $created.md];if {[file exists $note]} {file delete -- $note}}
        return -options $options $message
    } finally {if {[file exists $stage]} {file delete -force -- $stage}}
}
proc ::GX::_workspacePackageReferences {value depth resultName} {
    upvar 1 $resultName result
    if {$depth>64} {error {Workspace resource nesting exceeds limit}}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        set sha [dict get $value sha256]
        if {![regexp {^[a-f0-9]{64}$} $sha]} {error {Invalid packaged resource identity}}
        if {[dict exists $result $sha]&&[dict get $result $sha size_bytes]!=[dict get $value size_bytes]} {error {Conflicting resource sizes}}
        dict set result $sha $value
        _workspacePackageReferences [dict get $value metadata] [expr {$depth+1}] result
        return
    }
    if {[catch {llength $value} n]} return
    foreach item $value {if {$item ne $value} {_workspacePackageReferences $item [expr {$depth+1}] result}}
}
proc ::GX::sessionWorkspaceDialog {{parent .}} {
    set window .gxSessionWorkspaces;catch {destroy $window};toplevel $window
    wm title $window {Session Workspaces};wm transient $window $parent
    sessionWorkspaceBuild $window
    return $window
}
proc ::GX::sessionWorkspaceBuild {frame} {
    ttk::frame $frame.workspaces;set f $frame.workspaces;pack $f -fill both -expand 1
    ttk::treeview $f.tree -columns {name type provider preview} -show headings -height 5 -selectmode browse
    foreach {key label width} {name Name 230 type Type 160 provider Provider 150 preview Preview 70} {$f.tree heading $key -text $label;$f.tree column $key -width $width}
    ttk::scrollbar $f.scroll -command [list $f.tree yview];$f.tree configure -yscrollcommand [list $f.scroll set]
    pack $f.scroll -side right -fill y;pack $f.tree -fill both -expand 1
    ttk::frame $f.actions;pack $f.actions -fill x
    foreach {key title action} {refresh Refresh refresh open Open open notes {View notes} notes export Export export import Import import} {
        ttk::button $f.actions.$key -text $title -command [list ::GX::sessionWorkspaceGuiAction $f $action];pack $f.actions.$key -side left -padx 3
    }
    ttk::menubutton $f.actions.provider -text Actions -menu $f.actions.provider.menu
    menu $f.actions.provider.menu -tearoff 0 -postcommand [list ::GX::sessionWorkspaceActionMenu $f $f.actions.provider.menu]
    pack $f.actions.provider -side left -padx 3
    ttk::label $f.preview -text {Select a workspace to inspect its preview.};pack $f.preview -fill both
    bind $f.tree <Double-1> [list ::GX::sessionWorkspaceGuiAction $f open]
    dict set ::GX::SessionWorkspace::views $f {}
    bind $f.tree <<TreeviewSelect>> [list ::GX::sessionWorkspaceGuiAction $f inspect]
    sessionWorkspaceGuiAction $f refresh
}
proc ::GX::sessionWorkspaceGuiAction {frame action} {
    if {[catch {
        if {$action eq "refresh"} {
            $frame.tree delete [$frame.tree children {}]
            foreach workspace [sessionWorkspaceList] {$frame.tree insert {} end -id [dict get $workspace workspace_id] -values [list [dict get $workspace name] [dict get $workspace type] [dict get $workspace provider_id] [expr {[dict get $workspace preview] eq {}?"none":"available"}]]}
            return
        }
        if {$action eq "import"} {
            set path [workspaceOpenFile session_open_dir -title {Import workspace package} -filetypes {{{GX-TXT workspace ZIP} {.zip}}}]
            if {$path ne {}} {_sessionWorkspaceImportPath $path;sessionWorkspaceGuiAction $frame refresh};return
        }
        set id [$frame.tree selection];if {[llength $id]!=1} {error {Select one workspace}}
        switch $action {
            open {sessionWorkspaceOpen $id}
            notes {noteDocumentOpen $id view}
            export {
                set workspace [sessionWorkspaceGet $id]
                set path [workspaceSaveFile export_dir -title {Export workspace package} -initialfile "[dict get $workspace name].gxtxt-workspace.zip" -defaultextension .zip]
                if {$path ne {}} {
                    set resource [sessionWorkspaceExport $id]
                    set source [file join [_documentResourceRoot $id] [dict get $resource sha256].blob]
                    file copy -force -- $source $path
                }
            }
            inspect {
                set resource [dict get [sessionWorkspaceGet $id] preview]
                if {$resource eq {}} {$frame.preview configure -image {} -text {No preview};return}
                if {[dict get $resource metadata format] eq "image.png"} {
                    interactiveDocumentResourceInfo $resource
                    set imageName gxWorkspacePreview_[string map {. _} $frame]
                    catch {image delete $imageName}
                    image create photo $imageName -file [file join [_documentResourceRoot $id] [dict get $resource sha256].blob]
                    $frame.preview configure -image $imageName -text {}
                } else {$frame.preview configure -image {} -text {Vector scene preview available}}
            }
        }
    } message options] == 1} {tk_messageBox -parent [winfo toplevel $frame] -title Workspaces -icon error -message $message}
}
rename ::GX::buildSessionFileExplorerGui ::GX::buildSessionFileExplorerGui_workspace056_base
proc ::GX::buildSessionFileExplorerGui {} {
    buildSessionFileExplorerGui_workspace056_base
    set f .top.nb.sessionfiles
    if {![winfo exists $f.workspaceArea]} {
        ttk::labelframe $f.workspaceArea -text Workspaces
        sessionWorkspaceBuild $f.workspaceArea
    }
    sessionPageSelect
}
proc ::GX::managedResourceWriteBase64 {document metadata encoded} {
    if {[string length $encoded]>5592408} {error {Managed write exceeds the bounded 4 MiB data contract}}
    set bytes [binary decode base64 -strict $encoded]
    if {[string length $bytes]>4194304} {error {Managed write exceeds 4 MiB}}
    return [managedResourceWrite $document $metadata $bytes]
}
proc ::GX::managedResourceReadBase64 {reference start count} {return [binary encode base64 -maxlen 0 [interactiveDocumentResourceReadChunk $reference $start $count]]}
proc ::GX::managedResourceApiInfo {} {return [dict create api_id MANAGED_RESOURCE_API_v1 api_version 1 operations {write read info} write_bytes_max 4194304 read_bytes_max 1048576 arbitrary_paths 0]}
proc ::GX::noteDocumentApiInfo {} {return [dict create api_id NOTE_DOCUMENT_API_v1 api_version 1 operations {read write} storage UTF-8.md editor GX-Markup graphical_editor host_only]}

# Compare immutable subtrees before traversing them. Camera-only updates keep
# scientific records/resources byte-identical; walking every sampled value on
# pointer release would otherwise turn a tiny view change into a long UI stall.
# Changed branches still use the full resource parser and ownership validation.
proc ::GX::_workspaceChangedResourceReferences {value prior depth resultName} {
    upvar 1 $resultName result
    if {$value eq $prior} return
    if {$depth>64} {error {Workspace resource nesting exceeds limit}}
    if {![catch {dict get $value api_id} marker]&&$marker eq "INTERACTIVE_DOCUMENT_RESOURCE_API_v1"} {
        _workspacePackageReferences $value $depth result
        return
    }
    if {[catch {llength $value} n]} return
    if {[catch {llength $prior}]} {set prior {}}
    set index 0
    foreach item $value {
        if {$item ne $value} {_workspaceChangedResourceReferences $item [lindex $prior $index] [expr {$depth+1}] result}
        incr index
    }
}
proc ::GX::_workspacePreflightResources {payload {prior {}}} {
    set changed {}
    _workspaceChangedResourceReferences $payload $prior 0 changed
    dict for {sha resource} $changed {
        if {[_documentResourceDisposable [dict get $resource metadata]]} {_documentResourceIdentity $resource} else {interactiveDocumentResourceInfo $resource}
    }
}

# UI subscriptions contain widget paths only. Listing/identity continue to come
# from the existing Document registry; an idle refresh never owns saved state.
proc ::GX::sessionWorkspaceViewsChanged {} {
    if {![llength [info commands winfo]]} return
    if {$::GX::SessionWorkspace::views eq {} && $::GX::SessionWorkspace::titles eq {}} return
    if {$::GX::SessionWorkspace::refreshTimer eq {}} {set ::GX::SessionWorkspace::refreshTimer [after idle ::GX::sessionWorkspaceViewsRefresh]}
}
proc ::GX::sessionWorkspaceViewsRefresh {} {
    set ::GX::SessionWorkspace::refreshTimer {}
    sessionWorkspaceViewerTitlesRefresh
    # An empty Session page is a valid UI state. A Document token is meaningful
    # only while a Session is open; asking for one here used to raise at idle.
    if {$::GX::currentSession eq {}||![file isdirectory $::GX::currentSession]} {
        set signature [list no-session]
    } else {
        set signature [list [interactiveDocumentSessionToken]]
        foreach workspace [sessionWorkspaceList] {lappend signature [list [dict get $workspace workspace_id] [dict get $workspace name] [dict get $workspace type] [dict get $workspace provider_id] [dict get $workspace preview]]}
    }
    dict for {frame prior} $::GX::SessionWorkspace::views {
        if {![winfo exists $frame]} {dict unset ::GX::SessionWorkspace::views $frame;continue}
        if {$prior eq $signature} continue
        set selected [$frame.tree selection]
        sessionWorkspaceGuiAction $frame refresh
        if {[llength $selected]==1&&[$frame.tree exists $selected]} {$frame.tree selection set $selected}
        dict set ::GX::SessionWorkspace::views $frame $signature
    }
}
foreach command {sessionWorkspaceCreate sessionWorkspaceUpdate sessionWorkspaceRename sessionWorkspaceDelete sessionWorkspacePreviewSet _sessionWorkspaceImportPath} {
    rename ::GX::$command ::GX::${command}_workspace_ui_base
    proc ::GX::$command args [format {
        set result [::GX::%s_workspace_ui_base {*}$args]
        ::GX::sessionWorkspaceViewsChanged
        return $result
    } $command]
}
rename ::GX::sessionFileExplorerPopulate ::GX::sessionFileExplorerPopulate_workspace056_base
proc ::GX::sessionFileExplorerPopulate {} {
    set result [sessionFileExplorerPopulate_workspace056_base]
    sessionWorkspaceViewsChanged
    return $result
}

source [file join [file dirname [info script]] session_workspace_viewer_gui.tcl]
