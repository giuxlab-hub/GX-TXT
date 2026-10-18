# SPDX-License-Identifier: GPL-3.0-or-later
# Fixed headless public-owner operations for the shared development backend.
lassign $argv framework operation
set arguments [lrange $argv 2 end]
set argv0 __gxtxt_viewer_development_core_request__
source [file join [file normalize $framework] gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
try {
    switch $operation {
        new_design {
            if {[llength $arguments]!=1} {error {new_design requires one module ID}}
            set module [lindex $arguments 0]
            set d [::GX::viewerGuiDesignNew];dict set d module_id $module;dict set d title {Restricted C++ demonstration};dict set d provider_id development_example
            dict set d requirements NATIVE2D_VIEWPORT_HOST_v1 1
            dict set d components {{id readout type status parent inspector properties {text {Synthetic temperature · ready}} layout {row 0 column 0 sticky ew}} {id description type label parent inspector properties {text {C++ handler output appears here. No scientific Dataset is created.} wraplength 250} layout {row 1 column 0 sticky ew}} {id graphics type native2d parent canvas properties {title {RAM native demo}} layout {row 0 column 0 weight 1 sticky nsew}} {id advance type action parent toolbar properties {label {Run C++ handler} action advance} layout {row 0 column 0}}}
            dict set d handlers advance {arguments {window action} effect presentation label {Run C++ handler}}
            set result [::GX::viewerGuiDesignValidate $d]
        }
        validate_design {
            if {[llength $arguments]!=1} {error {validate_design requires one inert design path}}
            set result [::GX::viewerGuiDesignRead [lindex $arguments 0]]
        }
        numeric_add - numeric_sqrt {
            if {[llength $arguments]!=($operation eq {numeric_add}?2:1)} {error {Numeric SDK scalar argument count differs}}
            foreach value $arguments {::GX::uiFieldNormalize {type number} $value}
            set descriptor [file normalize [::GX::moduleField math.numeric descriptor]]
            if {$descriptor ne [file normalize [file join $::GX::scriptDir plugins modules math.numeric module.ini]]} {error {Numerical provider must be the trusted bundled public owner}}
            ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
            if {$operation eq {numeric_add}} {
                set result [::GX::NumericAPIv1::arrayBinary add [dict create kind scalar value [lindex $arguments 0]] [dict create kind scalar value [lindex $arguments 1]]]
            } else {set result [::GX::NumericAPIv1::arrayUnary sqrt [dict create kind scalar value [lindex $arguments 0]]]}
        }
        api_catalog {
            if {[llength $arguments]} {error {api_catalog takes no arguments}}
            set result {}
            foreach module $::GX::moduleOrder {
                set path [::GX::moduleField $module descriptor {}]
                if {$path eq {}} continue
                set d [::GX::parseIni $path]
                foreach api [::GX::splitList [::GX::descriptorValue $d public_apis ids {}]] {
                    set section public_api.$api
                    dict set result $api [dict create api_id $api version [::GX::descriptorValue $d $section api_version {}] provider $module enabled [::GX::moduleIsEnabled $module] capabilities [::GX::descriptorValue $d $section capabilities {}] documentation [::GX::descriptorValue $d $section documentation {}]]
                }
            }
            dict for {api command} [::GX::workbenchExtensionCoreApis] {
                regexp {_v([0-9]+)$} $api -> version
                dict set result $api [dict create api_id $api version $version provider CORE enabled [expr {[llength [info commands $command]]>0}] operations {} documentation docs/api/$api.md]
            }
            foreach {api command} {VIEWER_GUI_HOST_API_v1 ::GX::viewerGuiHostApiInfo VIEWER_COMPONENT_DEMO_API_v1 ::GX::viewerGuiComponentDemoApiInfo NATIVE_3D_GUI_HOST_API_v1 ::GX::native3DGuiHostApiInfo NATIVE_3D_GUI_HOST_API_v2 ::GX::native3DGuiHostApiInfoV2 NATIVE2D_TEMPORARY_DISPLAY_API_v1 ::GX::native2DTemporaryDisplayApiInfo NATIVE_PLOT_DISPLAY_API_v1 ::GX::nativePlotDisplayApiInfo SOURCE_SURFACE_API_v1 ::GX::sourceSurfaceApiInfo UI_FIELD_API_v1 ::GX::uiFieldApiInfo} {
                set meta [$command];dict set result $api [dict merge $meta [dict create api_id $api version [dict get $meta api_version] provider CORE enabled 1]]
            }
        }
        default {error {Unknown fixed development CORE operation}}
    }
    puts [dict create ok 1 result $result]
} on error {message options} {puts [dict create ok 0 error $message];exit 1}
