# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set out [file normalize $out]
if {![string match */_private_dev108/design-identity* $out] || [file exists $out]} {error {Requires a new private design identity fixture}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev108_design_identity_contract__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
package require Tk
wm withdraw .
proc ids design {set result {};foreach c [dict get $design components] {lappend result [dict get $c id]};return $result}
proc require {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
proc rejected {design label} {require {[catch {::GX::viewerGuiDesignValidate $design} reason]} "Admitted $label";dict set ::denials $label $reason}
set d [::GX::viewerGuiDesignNew {Stable SDK declaration identity}]
dict set d module_id viewer.development_workspace;dict set d provider_id development_workspace
dict set d handlers invoke {arguments {window action} effect presentation}
dict set d components [list \
    [dict create id early_action type action parent toolbar properties {label Invoke action invoke} layout {row 0 column 0}] \
    [dict create id outside type label parent inspector properties {text Outside} layout {row 0 column 0}] \
    [dict create id destination type panel parent inspector properties {title Destination} layout {row 1 column 0}] \
    [dict create id nested type panel parent destination properties {title Nested} layout {row 0 column 0}] \
    [dict create id leaf type label parent nested properties {text Leaf} layout {row 0 column 0}]]
set m [::GX::viewerGuiDesignModelCreate $d]
set moved [::GX::viewerGuiDesignModelEdit $m reparent early_action nested]
set md [dict get $moved design]
require {[ids $md] eq [ids $d]} {Reparent shifted restricted SDK declaration positions}
require {[dict get [lindex [dict get $md components] 0] parent] eq {nested}} {Reparent did not change intended parent}
set undo [::GX::viewerGuiDesignModelNavigate $moved undo]
require {[dict get $undo design] eq $d} {Undo differs from original design}
set redo [::GX::viewerGuiDesignModelNavigate $undo redo]
require {[dict get $redo design] eq $md} {Redo differs from stable reparent design}
set ::denials {}
foreach {parent label} {absent missing_parent leaf noncontainer_parent early_action self_cycle} {
    set bad $md;dict set bad components [lreplace [dict get $md components] 0 0 [dict replace [lindex [dict get $md components] 0] parent $parent]]
    rejected $bad $label
}
require {[catch {::GX::viewerGuiDesignModelEdit $moved reparent destination nested}]} {Container ancestor cycle admitted}
set duplicate [::GX::viewerGuiDesignModelEdit $moved duplicate destination]
set dd [dict get $duplicate design]
require {[lrange [ids $dd] 0 4] eq [ids $md]} {Duplicate changed existing identities}
require {[llength [ids $dd]]==9} {Duplicate lost non-parent-ordered descendants}
set removed [::GX::viewerGuiDesignModelEdit $moved remove destination]
require {[ids [dict get $removed design]] eq {outside}} {Remove lost deep descendant closure}
set copied {};set wanted {destination nested early_action leaf}
foreach item [::GX::_viewerGuiDesignParentOrder [dict get $md components]] {if {[dict get $item id] in $wanted} {lappend copied $item}}
set pasted [::GX::viewerGuiDesignModelEdit $moved paste $copied canvas [dict get $d handlers]]
require {[llength [ids [dict get $pasted design]]]==9} {Paste did not preserve subtree}
set w .stableIdentity
::GX::viewerGuiDesignCompose $md $w viewer.development_workspace development_workspace preview
set widgets [dict get $::GX::ViewerGui::instances $w widgets]
require {[winfo parent [dict get $widgets early_action]] eq [dict get $widgets nested]} {Actual native construction used declaration rather than dependency order}
require {[ids [dict get $::GX::ViewerGui::instances $w design]] eq [ids $d]} {Native composition changed SDK indices}
destroy $w
set pages [dict get $md components]
lappend pages [dict create id page_first type tab parent notebook properties {title First} layout {}] [dict create id page_second type tab parent notebook properties {title Second} layout {}] [dict create id notebook type tabs parent inspector properties {} layout {row 2 column 0}]
set tabbed [dict replace $md components $pages]
::GX::viewerGuiDesignCompose $tabbed $w viewer.development_workspace development_workspace preview
set widgets [dict get $::GX::ViewerGui::instances $w widgets]
[dict get $widgets notebook] select [dict get $widgets page_second]
set selected [::GX::viewerGuiDesignCapture $w]
require {[dict get $selected values notebook] eq {page_second}} {Capture lost native logical notebook selection}
[dict get $widgets notebook] select [dict get $widgets page_first]
::GX::viewerGuiDesignRestore $w $selected
require {[[dict get $widgets notebook] select] eq [dict get $widgets page_second]} {Restore lost native selected page}
set bad $selected;dict set bad values notebook outside
require {[catch {::GX::viewerGuiDesignRestore $w $bad}]} {Restored an unrelated component as a notebook page}
destroy $w
::GX::viewerGuiDesignSave [file join $out design.gxtxt-viewer] $md
require {[::GX::viewerGuiDesignRead [file join $out design.gxtxt-viewer]] eq $md} {Design Save/Open changed identity}
set f [open [file join $out result.tcldict] w];puts $f [dict create result PASS_OWNER_CONTRACT_ONLY ids [ids $md] construction_order [ids [dict replace $md components [::GX::_viewerGuiDesignParentOrder [dict get $md components]]]] denials $::denials gui_acceptance separate_independent_pointer_test];close $f
puts {PASS existing Design ownership, stable SDK identities, native construction and invalid parent rejection}
exit 0
