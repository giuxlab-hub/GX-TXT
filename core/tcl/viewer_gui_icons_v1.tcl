# SPDX-License-Identifier: GPL-3.0-or-later
# Additive resource operations of VIEWER_GUI_HOST_API_v1 / UI_FIELD_API_v1.
namespace eval ::GX::ViewerGui {variable iconValidation {};variable iconPhotos {};variable iconBindings {}}
proc ::GX::viewerGuiIconCatalog {} {
    set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
    if {[catch {exec [runtimeToolRequired python] -I -B $helper catalog} response]} {error "Shared icon catalog rejected: $response"}
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::viewerGuiIconImport {path title category license} {
    set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
    if {[catch {exec [runtimeToolRequired python] -I -B $helper import [file normalize $path] $title $category $license [runtimeToolRequired magick]} response]} {error "Icon import rejected: $response"}
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::viewerGuiIconImportSvg {source title category license} {
    if {[string length [encoding convertto utf-8 $source]]>262144} {error {Inline SVG exceeds 256 KiB}}
    set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
    if {[catch {exec [runtimeToolRequired python] -I -B $helper import_svg $title $category $license [runtimeToolRequired magick] << $source} response]} {error "Icon import rejected: $response"}
    if {![dict get $response ok]} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::viewerGuiIconsValidate {icons} {
    if {[dict size $icons]>64||[string bytelength $icons]>2097152} {error {Project icon catalog exceeds 64 icons / 2 MiB}}
    dict for {id asset} $icons {
        if {![regexp {^[a-z][a-z0-9_]{0,63}$} $id]} {error {Use a stable lowercase logical icon ID}}
        if {[dict exists $::GX::ViewerGui::iconValidation $asset]} continue
        set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
        if {[catch {exec [runtimeToolRequired python] -I -B $helper validate << $asset} response]} {error "Invalid project icon '$id': $response"}
        if {![dict get $response ok]} {error [dict get $response error]}
        if {[dict size $::GX::ViewerGui::iconValidation]>128} {set ::GX::ViewerGui::iconValidation {}}
        dict set ::GX::ViewerGui::iconValidation $asset 1
    }
    return $icons
}
proc ::GX::viewerGuiIconPhoto {asset size} {
    set pixels [dict get $asset png]
    set key [list [dict get $asset png_sha256] $size]
    if {[dict exists $::GX::ViewerGui::iconPhotos $key]} {return [dict get $::GX::ViewerGui::iconPhotos $key]}
    set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
    set response [exec [runtimeToolRequired python] -I -B $helper photo $size [runtimeToolRequired magick] << $asset]
    set image [image create photo -data [dict get $response result png] -format png]
    dict set ::GX::ViewerGui::iconPhotos $key $image
    return $image
}
proc ::GX::_viewerGuiIconPathPhoto {path size} {
    # Catalog-owned distributed PNG, not a new project resource/import.
    set f [open $path rb];try {set pixels [read $f 262145]} finally {close $f}
    if {[string length $pixels]>262144} {error {Catalog icon exceeds the shared icon resource bound}}
    set helper [file join $::GX::scriptDir core python gxtxt_viewer_icons.py]
    set response [exec [runtimeToolRequired python] -I -B $helper photo_png $size [runtimeToolRequired magick] << [binary encode base64 -maxlen 0 $pixels]]
    if {![dict get $response ok]} {error [dict get $response error]}
    return [image create photo -data [dict get $response result png] -format png]
}
proc ::GX::uiFieldIconApply {widget properties asset {catalog {}}} {
    set signature [list [ttk::style theme use] [tk scaling] $properties [dict get $asset png_sha256]]
    foreach property {icon_disabled icon_selected icon_hover} {
        set id [datasetPublicationV2DictDefault $properties $property {}]
        if {$id ne {} && [dict exists $catalog $id]} {lappend signature $property [dict get $catalog $id png_sha256]}
    }
    if {[dict exists $::GX::ViewerGui::iconBindings $widget signature] && [dict get $::GX::ViewerGui::iconBindings $widget signature] eq $signature} return
    if {![dict exists $::GX::ViewerGui::iconBindings $widget]} {
        bind $widget <<ThemeChanged>> +[list ::GX::_uiFieldIconThemeChanged $widget]
        bind $widget <Destroy> +[list ::GX::_uiFieldIconDestroyed $widget %W]
        if {![regexp {TipSchedule|TooltipShow} [bind $widget <Enter>]]} {
            bind $widget <Enter> +[list ::GX::_uiFieldIconTooltip $widget]
            bind $widget <Leave> +::GX::plotsToolbarTipHide
        }
    }
    set variants {};foreach key {icon_disabled icon_selected icon_hover} {set id [datasetPublicationV2DictDefault $properties $key {}];if {$id ne {} && [dict exists $catalog $id]} {dict set variants $id [dict get $catalog $id]}}
    dict set ::GX::ViewerGui::iconBindings $widget [dict create signature $signature properties $properties asset $asset catalog $variants]
    set presentation [datasetPublicationV2DictDefault $properties presentation icon_text]
    set placement [datasetPublicationV2DictDefault $properties icon_position left]
    set size [datasetPublicationV2DictDefault $properties icon_size 24]
    set size [expr {int($size*max(1.0,[tk scaling]/1.333333))}]
    if {$presentation eq {text_only}} {$widget configure -image {} -compound none;return}
    set images [list [viewerGuiIconPhoto $asset $size]]
    # Ttk selects the first matching state. Disabled overrides selected, which
    # overrides hover. Missing variants retain the normal native presentation.
    foreach {property state} {icon_disabled disabled icon_selected selected icon_hover active} {
        set id [datasetPublicationV2DictDefault $properties $property {}]
        if {$id eq {}} continue
        if {![dict exists $catalog $id]} {error "Missing project icon state resource: $id"}
        lappend images $state [viewerGuiIconPhoto [dict get $catalog $id] $size]
    }
    $widget configure -image $images -compound [expr {$presentation eq {icon_only}?{none}:$placement}]
    # The existing native label element exposes -space: it controls the actual
    # image/text gap, independently of the control's outside padding. Retain a
    # caller's base style; do not replace theme colors, layout, font or enablement.
    set base [$widget cget -style];if {$base eq {}} {set base [winfo class $widget]}
    set selectedStyle 0
    while {[regexp {^(GXSelected|GXIconSpace[0-9]+)\.(.+)$} $base -> wrapper original]} {
        if {$wrapper eq {GXSelected}} {set selectedStyle 1}
        set base $original
    }
    set space [expr {int([datasetPublicationV2DictDefault $properties icon_spacing 4]*max(1.0,[tk scaling]/1.333333))}]
    set style GXIconSpace${space}.$base
    ttk::style configure $style -space $space
    $widget configure -style $style
    if {$selectedStyle} {native2DViewportToolState $widget [expr {{selected} in [$widget state]}]}
}
proc ::GX::_uiFieldIconTooltip {widget} {
    if {![dict exists $::GX::ViewerGui::iconBindings $widget properties]} return
    set p [dict get $::GX::ViewerGui::iconBindings $widget properties]
    if {[datasetPublicationV2DictDefault $p presentation icon_text] ne {icon_only}} return
    set text [datasetPublicationV2DictDefault $p tooltip [$widget cget -text]]
    if {$text ne {}} {plotsToolbarTipSchedule $widget $text}
}
proc ::GX::_uiFieldIconThemeChanged {widget} {
    if {![winfo exists $widget] || ![dict exists $::GX::ViewerGui::iconBindings $widget]} return
    set record [dict get $::GX::ViewerGui::iconBindings $widget]
    uiFieldIconApply $widget [dict get $record properties] [dict get $record asset] [dict get $record catalog]
}
proc ::GX::_uiFieldIconDestroyed {widget actual} {
    if {$widget eq $actual && [dict exists $::GX::ViewerGui::iconBindings $widget]} {dict unset ::GX::ViewerGui::iconBindings $widget}
}
proc ::GX::viewerGuiIconEdit {design operation args} {
    set icons [datasetPublicationV2DictDefault $design icons {}]
    switch $operation {
        put {
            lassign $args id asset
            dict set icons $id $asset
        }
        rename {
            lassign $args old id
            if {![dict exists $icons $old]||[dict exists $icons $id]} {error {Choose an existing source and unused target icon ID}}
            dict set icons $id [dict get $icons $old];dict unset icons $old
            set components {}
            foreach c [dict get $design components] {
                foreach key {icon icon_disabled icon_hover icon_selected} {if {[dict exists $c properties $key]&&[dict get $c properties $key] eq $old} {dict set c properties $key $id}}
                if {[dict exists $c properties command_icons]} {
                    dict for {command p} [dict get $c properties command_icons] {
                        foreach key {icon icon_disabled icon_hover icon_selected} {if {[dict exists $p $key] && [dict get $p $key] eq $old} {dict set p $key $id}}
                        dict set c properties command_icons $command $p
                    }
                }
                lappend components $c
            }
            dict set design components $components
        }
        remove {
            set id [lindex $args 0]
            foreach c [dict get $design components] {
                set bindings [list [dict get $c properties]]
                if {[dict exists $c properties command_icons]} {lappend bindings {*}[dict values [dict get $c properties command_icons]]}
                foreach p $bindings {foreach key {icon icon_disabled icon_hover icon_selected} {if {[dict exists $p $key]&&[dict get $p $key] eq $id} {error {Remove bindings before deleting a referenced icon}}}}
            }
            dict unset icons $id
        }
        default {error {Unknown public icon catalog edit}}
    }
    dict set design icons [viewerGuiIconsValidate $icons]
    return $design
}
proc ::GX::_viewerGuiCommandIconsValidate {type properties icons} {
    if {![dict exists $properties command_icons]} return
    if {$type ni {command_toolbar menu context_menu}} {error {Command icons belong to native command containers}}
    dict for {command p} [dict get $properties command_icons] {
        if {$command ni [dict get $properties actions]} {error {Icon target must be an existing command in this container}}
        dict for {key value} $p {if {$key ni {icon icon_disabled icon_hover icon_selected presentation icon_position icon_size icon_spacing}} {error {Unknown command icon presentation property}}}
        set id [datasetPublicationV2DictDefault $p icon {}]
        if {$id eq {} || ![dict exists $icons $id]} {error {Command icon requires an existing normal project resource}}
        foreach key {icon_disabled icon_hover icon_selected} {set id [datasetPublicationV2DictDefault $p $key {}];if {$id ne {} && ![dict exists $icons $id]} {error {Missing command state icon resource}}}
        if {[datasetPublicationV2DictDefault $p presentation icon_text] ni {icon_only text_only icon_text} || [datasetPublicationV2DictDefault $p icon_position left] ni {left right top bottom} || [datasetPublicationV2DictDefault $p icon_size 24] ni {16 24 32 48} || [datasetPublicationV2DictDefault $p icon_spacing 4] ni {0 2 4 6 8 12}} {error {Invalid typed command icon presentation}}
        if {$type in {menu context_menu}} {
            if {[datasetPublicationV2DictDefault $p presentation icon_text] eq {icon_only} || [datasetPublicationV2DictDefault $p icon_hover {}] ne {} || [datasetPublicationV2DictDefault $p icon_selected {}] ne {} || [datasetPublicationV2DictDefault $p icon_spacing 0]!=0} {error {Native command menus support text or image+text, normal/disabled images and native placement; hover/selected image variants, icon-only tooltips and custom image/text spacing are unavailable}}
        }
    }
}
proc ::GX::uiFieldMenuIconApply {menu index properties asset {catalog {}}} {
    set size [expr {int([datasetPublicationV2DictDefault $properties icon_size 24]*max(1.0,[tk scaling]/1.333333))}]
    set image {}
    if {[datasetPublicationV2DictDefault $properties presentation icon_text] ne {text_only}} {
        set disabled [datasetPublicationV2DictDefault $properties icon_disabled {}]
        if {[$menu entrycget $index -state] eq {disabled} && $disabled ne {}} {set asset [dict get $catalog $disabled]}
        set image [viewerGuiIconPhoto $asset $size]
    }
    $menu entryconfigure $index -image $image -compound [datasetPublicationV2DictDefault $properties icon_position left]
}
proc ::GX::_viewerGuiCommandIconsMount {window} {
    set instance [dict get $::GX::ViewerGui::instances $window]
    set catalog [datasetPublicationV2DictDefault [dict get $instance design] icons {}]
    foreach component [dict get $instance design components] {
        set p [dict get $component properties]
        if {![dict exists $p command_icons]} continue
        set type [dict get $component type];set widget [dict get $instance widgets [dict get $component id]]
        dict for {command presentation} [dict get $p command_icons] {
            if {$type eq {command_toolbar}} {
                set button [dict get $::GX::ViewerCommands::windows $window toolbar buttons $command]
                uiFieldIconApply $button $presentation [dict get $catalog [dict get $presentation icon]] $catalog
            } else {
                dict for {tracked action} [datasetPublicationV2DictDefault [dict get $::GX::ViewerCommands::windows $window] menus {}] {
                    lassign $tracked menu index
                    if {$menu ne $widget || $action ne $command} continue
                    dict set ::GX::ViewerCommands::windows $window menu_icon_bindings [list $menu $index] [dict create properties $presentation asset [dict get $catalog [dict get $presentation icon]] catalog $catalog]
                    uiFieldMenuIconApply $menu $index $presentation [dict get $catalog [dict get $presentation icon]] $catalog
                }
            }
        }
    }
    viewerCommandToolbarRefresh $window
}
