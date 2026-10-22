# SPDX-License-Identifier: GPL-3.0-or-later
# Typed presentation of the original canonical Workbench3D owner. No geometry
# algorithms, renderer, model, resource or scientific History are duplicated.
proc ::GX::_viewerGuiWorkbenchDesignValidate {design} {
    set definitions {};set forms {};set targets {}
    foreach c [dict get $design components] {dict set definitions [dict get $c id] $c}
    foreach c [dict get $design components] {
        set p [dict get $c properties]
        if {![dict exists $p workbench_parameters]} continue
        if {[dict get $c type] ne {section} || ![dict exists $design requirements WORKBENCH_3D_API_v1] || [dict get $design requirements WORKBENCH_3D_API_v1]!=1} {error {Editable geometry requires a declared WORKBENCH_3D_API_v1@1 section}}
        if {[lsort [dict keys [dict get $p workbench_parameters]]] ne [lsort {primitive x y z radius height name}]} {error {Geometry primitive form requires its complete typed parameter mapping}}
        dict for {key id} [dict get $p workbench_parameters] {
            if {![dict exists $definitions $id] || [dict get $definitions $id type] ni {field entry choice combobox}} {error "Invalid geometry parameter field: $key"}
            if {$key eq {primitive} && [dict get $definitions $id type] ni {choice combobox}} {error {Geometry primitive kind requires a declared choice}}
        }
        foreach {key types} {workbench_viewport editable3d workbench_documents {choice combobox} workbench_objects {choice combobox} workbench_unit {label status} workbench_status {label status log}} {
            if {![dict exists $p $key] || ![dict exists $definitions [dict get $p $key]] || [dict get $definitions [dict get $p $key] type] ni $types} {error "Missing or invalid geometry form reference: $key"}
        }
        if {[dict exists $p workbench_selection] != [dict exists $p workbench_selection_mode]} {error {Declare both workbench_selection and workbench_selection_mode for multiple selection}}
        if {[dict exists $p workbench_selection]} {
            set list [dict get $p workbench_selection];set mode [dict get $p workbench_selection_mode]
            if {![dict exists $definitions $list] || [dict get $definitions $list type] ne {list} || [datasetPublicationV2DictDefault [dict get $definitions $list properties] selectmode browse] ni {multiple extended}} {error {Workbench multiple selection requires a declared extended or multiple list}}
            if {![dict exists $definitions $mode] || [dict get $definitions $mode type] ni {choice combobox} || [lsort [dict get $definitions $mode properties choices]] ne {add replace subtract}} {error {Workbench selection mode requires replace, add and subtract choices}}
        }
        lappend forms [dict get $c id];lappend targets [dict get $p workbench_viewport]
    }
    if {[llength $forms]>1} {error {The existing editable Native3D owner supports one geometry form per Viewer}}
    # Builder creates components incrementally. An unbound declared viewport is
    # an inert placeholder; no scientific command is admitted without the form.
    set viewports 0;foreach c [dict get $design components] {if {[dict get $c type] eq {editable3d}} {incr viewports}}
    if {$viewports>1} {error {The existing editable Native3D owner supports one viewport per Viewer}}
}
proc ::GX::_viewerGuiWorkbenchForm {window form} {
    if {![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window token] eq {}} {error {Open a Session and reopen the geometry Viewer}}
    set c [viewerGuiDesignComponent $window $form]
    if {[dict get $c type] ne {section} || ![dict exists $c properties workbench_parameters]} {error {Declare the complete canonical geometry form}}
    modulePublicApiActivate viewer.3d_workbench WORKBENCH_3D_API_v1
    return [dict get $c properties]
}
proc ::GX::_viewerGuiWorkbenchOwned {window form} {
    if {![viewerGuiDesignGuard $window] || [dict get $::GX::ViewerGui::instances $window token] eq {}} {return 0}
    set p [_viewerGuiWorkbenchForm $window $form]
    set parent [dict get $::GX::ViewerGui::instances $window widgets [dict get $p workbench_viewport]]
    return [expr {$::GX::Engine3D::window eq "$parent.native3d" && [winfo exists "$parent.native3d"]}]
}
proc ::GX::_viewerGuiWorkbenchRefresh {window form} {
    set p [_viewerGuiWorkbenchForm $window $form]
    set documents {};foreach item [interactiveDocumentList viewer.3d_workbench workbench_3d] {lappend documents [dict get $item id]}
    viewerGuiDesignChoicesSet $window [dict get $p workbench_documents] $documents
    set info [dict create status unbound owner viewer.3d_workbench/workbench_3d]
    if {[_viewerGuiWorkbenchOwned $window $form]} {set info [::GX::Workbench3D::guiInspect]}
    set retainPending 0;set pendingIds {}
    if {[dict exists $p workbench_selection] && [dict exists $::GX::ViewerGui::instances $window workbench_forms $form]} {
        set previous [dict get $::GX::ViewerGui::instances $window workbench_forms $form]
        if {[dict get $info status] eq {ready} && [dict get $previous status] eq {ready} && [dict get $previous document_id] eq [dict get $info document_id] && [dict get $previous generation] eq [dict get $info generation] && [dict get $previous selected] eq [dict get $info selected]} {
            # A presentation refresh (including compiled OPEN) must not replace
            # independent pending controls with unchanged native selection.
            # Capture canonical IDs before refreshing/reordering the list rows.
            set retainPending 1
            set list [dict get $::GX::ViewerGui::instances $window widgets [dict get $p workbench_selection]]
            foreach index [$list curselection] {lappend pendingIds [$list get $index]}
        }
    }
    set objects {}
    if {[dict get $info status] eq {ready}} {
        set objects [concat [dict keys [dict get $info objects]] [dict keys [dict get $info profiles]]]
        viewerGuiDesignValueSet $window [dict get $p workbench_documents] [dict get $info document_id]
        viewerGuiDesignTextSet $window [dict get $p workbench_unit] [dict get $info working_unit]
        set message [dict get $info message]
        set notice [datasetPublicationV2DictDefault $info recovery_notice {}]
        if {$notice ne {} && [string first $notice $message]<0} {set message [string trim "$message $notice"]}
        viewerGuiDesignTextSet $window [dict get $p workbench_status] "Document [dict get $info document_id]; revision [dict get $info revision]; [llength $objects] objects/profiles; Undo [dict get $info undo_count]; Redo [dict get $info redo_count]. $message"
        set context [viewerGuiDesignContextGet $window]
        dict set context workbench_documents $form [dict create document_id [dict get $info document_id] generation [dict get $info generation]]
        viewerGuiDesignContextSet $window $context
    } else {
        viewerGuiDesignTextSet $window [dict get $p workbench_unit] {}
        viewerGuiDesignTextSet $window [dict get $p workbench_status] {Open or create a canonical 3D Document.}
    }
    viewerGuiDesignChoicesSet $window [dict get $p workbench_objects] $objects
    set single [dict get $p workbench_objects]
    if {[dict get [viewerGuiDesignValues $window] $single] ni $objects} {viewerGuiDesignValueSet $window $single {}}
    if {[dict exists $p workbench_selection]} {
        set field [dict get $p workbench_selection]
        viewerGuiDesignChoicesSet $window $field $objects
        set indices {}
        if {$retainPending} {
            foreach id $pendingIds {set index [lsearch -exact $objects $id];if {$index>=0} {lappend indices $index}}
        } elseif {[dict get $info status] eq {ready}} {
            foreach id [dict get $info selected] {set index [lsearch -exact $objects $id];if {$index>=0} {lappend indices $index}}
        }
        viewerGuiDesignValueSet $window $field $indices
    }
    if {!$retainPending && [dict get $info status] eq {ready} && [llength [dict get $info selected]]==1} {viewerGuiDesignValueSet $window [dict get $p workbench_objects] [lindex [dict get $info selected] 0]}
    dict set ::GX::ViewerGui::instances $window workbench_forms $form $info
    return $info
}
proc ::GX::_viewerGuiWorkbenchInitialize {window} {
    dict set ::GX::ViewerGui::instances $window workbench_forms {}
    foreach c [dict get $::GX::ViewerGui::instances $window design components] {
        if {![dict exists $c properties workbench_parameters]} continue
        set form [dict get $c id]
        dict set ::GX::ViewerGui::instances $window workbench_forms $form {status unbound}
        if {[dict exists $c properties workbench_selection]} {
            set single [dict get $c properties workbench_objects]
            if {[dict get [viewerGuiDesignComponent $window $single] type] eq {choice}} {
                # UIField validates the scalar first and suppresses unchanged
                # scalar callbacks. An explicit singleton choice still needs
                # to replace local multiple candidates, even at the same value.
                set widget [dict get $::GX::ViewerGui::instances $window widgets $single]
                bind $widget.entry <<ComboboxSelected>> +[list ::GX::viewerGuiDesignFieldChanged $window $single]
            }
        }
        # Builder's component demonstration never activates a scientific owner.
        if {[dict get $::GX::ViewerGui::instances $window mode] ne {demo} && [dict get $::GX::ViewerGui::instances $window token] ne {}} {_viewerGuiWorkbenchRefresh $window $form}
    }
}
proc ::GX::_viewerGuiWorkbenchAssociationCheck {component association} {
    if {[dict get $component type] ne {section} || ![dict exists $component properties workbench_parameters]} {error {Saved geometry association names an undeclared geometry form}}
    if {[lsort [dict keys $association]] ne {document_id generation}} {error {Invalid saved canonical geometry association}}
    set d [interactiveDocumentRead [dict get $association document_id]]
    if {[dict get $d module_id] ne {viewer.3d_workbench} || [dict get $d provider_id] ne {workbench_3d} || [dict get $d format] ne {workbench3d.document.v1} || [dict get $d generation] ne [dict get $association generation]} {error {Saved geometry Document was deleted, replaced or has another canonical owner}}
    return $d
}
proc ::GX::_viewerGuiWorkbenchRestoreCheck {window context} {
    dict for {form association} [datasetPublicationV2DictDefault $context workbench_documents {}] {
        _viewerGuiWorkbenchForm $window $form
        _viewerGuiWorkbenchAssociationCheck [viewerGuiDesignComponent $window $form] $association
    }
}
proc ::GX::_viewerGuiWorkbenchRestore {window} {
    dict for {form association} [datasetPublicationV2DictDefault [viewerGuiDesignContextGet $window] workbench_documents {}] {
        set p [_viewerGuiWorkbenchForm $window $form]
        set values [viewerGuiDesignValues $window];set candidates {}
        if {[dict exists $p workbench_selection]} {
            set field [dict get $p workbench_selection]
            set widget [dict get $::GX::ViewerGui::instances $window widgets $field]
            set rows [$widget get 0 end]
            foreach index [dict get $values $field] {
                if {![string is integer -strict $index] || $index<0 || $index>=[llength $rows]} {error {Saved geometry candidate index is outside its declared object list}}
                lappend candidates [lindex $rows $index]
            }
        }
        _viewerGuiWorkbenchMount $window $form [dict get $association document_id]
        if {[dict exists $p workbench_selection]} {
            # Mount refreshes the native selection projection. Saved pending
            # candidates are distinct local controls: restore their canonical
            # IDs against the new row order without invoking scientific Select.
            set rows [$widget get 0 end];set indices {}
            foreach id $candidates {
                set index [lsearch -exact $rows $id]
                if {$index<0} {error "Saved geometry candidate '$id' is unavailable in the current Document"}
                lappend indices $index
            }
            set single [dict get $p workbench_objects];set id [dict get $values $single]
            if {$id ne {} && $id ni $rows} {error "Saved geometry shortcut '$id' is unavailable in the current Document"}
            viewerGuiDesignValueSet $window $single $id
            viewerGuiDesignValueSet $window $field $indices
        }
    }
}
proc ::GX::_viewerGuiWorkbenchChanged {window form} {
    if {![winfo exists $window] || ![dict exists $::GX::ViewerGui::instances $window] || ![viewerGuiDesignGuard $window]} return
    if {![_viewerGuiWorkbenchOwned $window $form]} return
    if {[catch {_viewerGuiWorkbenchRefresh $window $form} message]} {
        set p [_viewerGuiWorkbenchForm $window $form]
        viewerGuiDesignTextSet $window [dict get $p workbench_status] "Geometry presentation refresh failed: $message"
        viewerGuiTraceEmit $window $form error [dict create operation geometry_refresh message $message]
    }
}
proc ::GX::_viewerGuiWorkbenchMount {window form document} {
    set p [_viewerGuiWorkbenchForm $window $form]
    set parent [dict get $::GX::ViewerGui::instances $window widgets [dict get $p workbench_viewport]]
    if {[winfo exists $::GX::Engine3D::window] && $::GX::Engine3D::window ne "$parent.native3d"} {error {Close the existing editable Native3D host before opening another geometry editor}}
    # Existing owner rejects a different active Document, stale resource or busy
    # native operation before any model substitution. Never force-close it.
    set mounted [::GX::Workbench3D::guiMount $parent [dict create workspace_id $document]]
    # guiMount returns an embedded host; its caller owns placement in the
    # declared component. Managing only its descendants leaves the native
    # canvas unmapped, even though the canonical geometry is ready.
    pack $mounted -fill both -expand 1
    bind $parent <<GXWorkbench3DChanged>> [list ::GX::_viewerGuiWorkbenchChanged $window $form]
    if {[winfo exists $parent.empty]} {destroy $parent.empty}
    set info [_viewerGuiWorkbenchRefresh $window $form]
    dict set ::GX::ViewerGui::instances $window workbench_saved $form [_viewerGuiWorkbenchStamp $info]
    return $info
}
proc ::GX::_viewerGuiWorkbenchStamp info {
    return [list [dict get $info document_id] [dict get $info generation] [dict get $info revision] [dict get $info sha256]]
}
proc ::GX::_viewerGuiWorkbenchSelectionFieldChanged {window component} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    foreach definition [dict get $instance design components] {
        set p [dict get $definition properties]
        if {![dict exists $p workbench_parameters] || ![dict exists $p workbench_selection]} continue
        set single [dict get $p workbench_objects];set multiple [dict get $p workbench_selection]
        if {$component ni [list $single $multiple]} continue
        set widget [dict get $instance widgets $multiple];set rows [$widget get 0 end]
        if {$component eq $single} {
            set index [lsearch -exact $rows $::GX::ViewerGui::values($window,$single)]
            viewerGuiDesignValueSet $window $multiple [expr {$index<0 ? {} : [list $index]}]
        } else {
            set indices $::GX::ViewerGui::values($window,$multiple)
            if {[llength $indices]==1} {
                set index [lindex $indices 0]
                if {[string is integer -strict $index] && $index>=0 && $index<[llength $rows]} {viewerGuiDesignValueSet $window $single [lindex $rows $index]}
            }
        }
        # These are local candidate controls. The existing Select command
        # alone validates current canonical identities and applies selection.
        return
    }
}
proc ::GX::_viewerGuiWorkbenchDirty {window form} {
    if {![_viewerGuiWorkbenchOwned $window $form]} {return 0}
    set info [::GX::Workbench3D::guiInspect]
    if {[dict get $info status] ne {ready}} {return 0}
    return [expr {[_viewerGuiWorkbenchStamp $info] ne [datasetPublicationV2DictDefault [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] workbench_saved {}] $form {}]}]
}
proc ::GX::_viewerGuiWorkbenchSave {window form} {
    if {![_viewerGuiWorkbenchOwned $window $form]} {error {Open this Viewer's canonical 3D Document first}}
    set info [::GX::Workbench3D::guiCommand save]
    dict set ::GX::ViewerGui::instances $window workbench_saved $form [_viewerGuiWorkbenchStamp $info]
    return $info
}
proc ::GX::viewerGuiDesignWorkbenchCommand {window form operation} {
    set p [_viewerGuiWorkbenchForm $window $form]
    set values [viewerGuiDesignValues $window]
    switch -- $operation {
        refresh {return [_viewerGuiWorkbenchRefresh $window $form]}
        new {return [_viewerGuiWorkbenchMount $window $form new]}
        open {
            set document [dict get $values [dict get $p workbench_documents]]
            if {$document eq {}} {error {Choose an existing canonical 3D Document}}
            return [_viewerGuiWorkbenchMount $window $form $document]
        }
        primitive - save - undo - redo - select - inspect - close {
            if {![_viewerGuiWorkbenchOwned $window $form]} {error {Open this Viewer's canonical 3D Document first}}
        }
        default {
            if {$operation ni [::GX::Workbench3D::guiFormCommands]} {error {Unsupported finite geometry form command}}
            if {![_viewerGuiWorkbenchOwned $window $form]} {error {Open this Viewer's canonical 3D Document first}}
        }
    }
    if {$operation eq {close}} {
        if {[_viewerGuiWorkbenchDirty $window $form]} {error {Save the canonical geometry Document before closing its editable host}}
        ::GX::Workbench3D::guiCommand close
        set context [viewerGuiDesignContextGet $window]
        if {[dict exists $context workbench_documents $form]} {dict unset context workbench_documents $form}
        viewerGuiDesignContextSet $window $context
        return [_viewerGuiWorkbenchRefresh $window $form]
    } elseif {$operation eq {primitive}} {
        set fields {};dict for {key id} [dict get $p workbench_parameters] {dict set fields $key [dict get $values $id]}
        ::GX::Workbench3D::guiCommand primitive [dict create primitive [dict get $fields primitive] dimensions [list [dict get $fields x] [dict get $fields y] [dict get $fields z]] radius [dict get $fields radius] height [dict get $fields height] name [dict get $fields name]]
    } elseif {$operation eq {select}} {
        if {[dict exists $p workbench_selection]} {
            set projected [dict get $::GX::ViewerGui::instances $window workbench_forms $form]
            set current [::GX::Workbench3D::guiInspect]
            if {[dict get $projected status] ne {ready} || [_viewerGuiWorkbenchStamp $projected] ne [_viewerGuiWorkbenchStamp $current]} {error {Geometry selection list changed; refresh before selecting its current objects}}
            set ids [concat [dict keys [dict get $current objects]] [dict keys [dict get $current profiles]]]
            set field [dict get $p workbench_selection]
            set widget [dict get $::GX::ViewerGui::instances $window widgets $field]
            if {[$widget get 0 end] ne $ids} {error {Geometry selection list no longer represents the current canonical objects}}
            set wanted {}
            foreach index [dict get $values $field] {
                if {![string is integer -strict $index] || $index<0 || $index>=[llength $ids]} {error {Geometry selection index is outside the current canonical list}}
                lappend wanted [lindex $ids $index]
            }
            ::GX::Workbench3D::selectionApply $wanted [dict get $values [dict get $p workbench_selection_mode]]
        } else {
            set id [dict get $values [dict get $p workbench_objects]]
            ::GX::Workbench3D::selectionSet [expr {$id eq {} ? {} : [list $id]}]
        }
    } elseif {$operation eq {save}} {
        _viewerGuiWorkbenchSave $window $form
    } else {
        ::GX::Workbench3D::guiCommand $operation
    }
    set info [_viewerGuiWorkbenchRefresh $window $form]
    # A planar handoff may successfully move the shared editable host to the
    # Curve/Native3D workflow. The originating form is then genuinely unbound;
    # its refresh must not require a current geometry Document or turn that
    # successful handoff into a failed compiled-Viewer event.
    set detail [dict create operation $operation status [dict get $info status]]
    foreach key {document_id generation revision sha256} {
        if {[dict exists $info $key]} {dict set detail $key [dict get $info $key]}
    }
    viewerGuiTraceEmit $window $form geometry $detail
    return $info
}
