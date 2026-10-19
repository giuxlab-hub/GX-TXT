# SPDX-License-Identifier: GPL-3.0-or-later
# Additive Native2D geometry contract for discrete symbol/port diagrams.
# Interactive Document remains the sole persistent authority. Geometry is a
# projection, not connectivity: only explicit stable endpoint references join.
namespace eval ::GX::Native2DDiagram {variable catalogs {}}
proc ::GX::_native2DDiagramId {value} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_.-]{0,63}$} $value]} {error {Invalid stable diagram identifier}}
    return $value
}
proc ::GX::_native2DDiagramPoint {point} {
    if {[llength $point]!=2} {error {Diagram point requires two coordinates}}
    foreach value $point {if {![string is double -strict $value] || [catch {expr {abs(double($value))<=1000000}} finite] || !$finite} {error {Diagram coordinate must be finite within +/-1000000}}}
    return $point
}
proc ::GX::native2DGeometryDiagramCatalogRegister {id descriptor} {
    _native2DDiagramId $id
    foreach key {module_id version license symbols} {if {![dict exists $descriptor $key]} {error "Symbol catalog requires $key"}}
    _interactiveDocumentValidateOwner [dict get $descriptor module_id] $id
    if {[string bytelength $descriptor]>131072 || [dict size [dict get $descriptor symbols]]>64} {error {Symbol catalog exceeds bounded Native2D contract}}
    dict for {kind symbol} [dict get $descriptor symbols] {
        _native2DDiagramId $kind
        foreach key {title prefix paths pins attributes} {if {![dict exists $symbol $key]} {error "Symbol requires $key"}}
        _native2DDiagramId [dict get $symbol prefix]
        if {[llength [dict get $symbol paths]]>32 || [dict size [dict get $symbol pins]]>16} {error {Symbol geometry/pins exceed bounds}}
        foreach path [dict get $symbol paths] {
            if {[llength $path]<2 || [llength $path]>128} {error {Symbol path requires 2..128 vertices}}
            foreach point $path {_native2DDiagramPoint $point}
        }
        dict for {pin point} [dict get $symbol pins] {_native2DDiagramId $pin;_native2DDiagramPoint $point}
        dict for {attribute field} [dict get $symbol attributes] {
            _native2DDiagramId $attribute
            if {![dict exists $field type] || [dict get $field type] ni {number string choice} || ![dict exists $field default]} {error {Symbol attribute requires typed default}}
        }
    }
    dict set ::GX::Native2DDiagram::catalogs $id $descriptor
    return $id
}
proc ::GX::native2DGeometryDiagramCatalog {{id {}}} {
    if {$id eq {}} {return $::GX::Native2DDiagram::catalogs}
    if {![dict exists $::GX::Native2DDiagram::catalogs $id]} {error {Unknown registered symbol catalog}}
    return [dict get $::GX::Native2DDiagram::catalogs $id]
}
proc ::GX::_native2DDiagramAttributes {symbol attributes} {
    set schema [dict get $symbol attributes];set result {}
    dict for {key value} $attributes {if {![dict exists $schema $key]} {error "Unknown symbol attribute '$key'"}}
    dict for {key field} $schema {
        set value [datasetPublicationV2DictDefault $attributes $key [dict get $field default]]
        if {[string bytelength $value]>256 || [regexp {[\x00\r\n]} $value]} {error {Diagram attribute exceeds single-line text bounds}}
        switch [dict get $field type] {
            number {if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {error "Attribute '$key' requires finite numeric SI value"};foreach {bound relation} {min < max >} {if {[dict exists $field $bound] && [expr "$value $relation [dict get $field $bound]"]} {error "Attribute '$key' violates $bound"}}}
            choice {if {$value ni [dict get $field values]} {error "Attribute '$key' is outside catalog choices"}}
        }
        dict set result $key $value
    }
    return $result
}
proc ::GX::native2DGeometryDiagramValidate {payload} {
    if {[string bytelength $payload]>1048576} {error {Diagram payload exceeds 1 MiB}}
    if {[lsort [dict keys $payload]] ne [lsort {schema catalog next_id components junctions wires labels}]} {error {Unsupported Native2D diagram payload fields}}
    if {[dict get $payload schema] ne {gxtxt.native2d.diagram.v1}} {error {Unsupported diagram schema}}
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    if {![string is entier -strict [dict get $payload next_id]] || [dict get $payload next_id]<1} {error {Invalid diagram allocation counter}}
    foreach {collection maximum} {components 256 junctions 512 wires 1024 labels 256} {if {[dict size [dict get $payload $collection]]>$maximum} {error "Diagram $collection exceeds $maximum"}}
    set ids {}
    dict for {id item} [dict get $payload components] {
        _native2DDiagramId $id
        if {$id in $ids} {error {Duplicate diagram identity}};lappend ids $id
        if {[lsort [dict keys $item]] ne [lsort {kind name position rotation attributes}]} {error {Invalid symbol instance fields}}
        set symbol [dict get $catalog symbols [dict get $item kind]]
        _native2DDiagramId [dict get $item name]
        _native2DDiagramPoint [dict get $item position]
        if {[dict get $item rotation] ni {0 90 180 270}} {error {Diagram rotation requires a quarter turn}}
        _native2DDiagramAttributes $symbol [dict get $item attributes]
    }
    set names {}
    dict for {id item} [dict get $payload components] {set name [dict get $item name];if {$name in $names} {error {Duplicate component name}};lappend names $name}
    dict for {id point} [dict get $payload junctions] {_native2DDiagramId $id;if {$id in $ids} {error {Duplicate diagram identity}};lappend ids $id;_native2DDiagramPoint $point}
    dict for {id wire} [dict get $payload wires] {
        _native2DDiagramId $id
        if {$id in $ids} {error {Duplicate diagram identity}};lappend ids $id
        if {[lsort [dict keys $wire]] ne {end route start}} {error {Invalid wire fields}}
        foreach endpoint {start end} {native2DGeometryDiagramEndpoint $payload [dict get $wire $endpoint]}
        if {[dict get $wire start] eq [dict get $wire end]} {error {Wire endpoints must differ}}
        if {[llength [dict get $wire route]]>128} {error {Wire route exceeds 128 corners}}
        foreach point [dict get $wire route] {_native2DDiagramPoint $point}
    }
    dict for {id label} [dict get $payload labels] {
        _native2DDiagramId $id
        if {$id in $ids} {error {Duplicate diagram identity}};lappend ids $id
        if {![dict exists $label endpoint] || ![dict exists $label text]} {error {Label requires endpoint and text}}
        foreach key [dict keys $label] {if {$key ni {endpoint text offset}} {error {Invalid label fields}}}
        if {[dict exists $label offset]} {_native2DDiagramPoint [dict get $label offset]}
        native2DGeometryDiagramEndpoint $payload [dict get $label endpoint]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,31}$} [dict get $label text]]} {error {Net label must be a bounded identifier}}
    }
    return $payload
}
proc ::GX::native2DGeometryDiagramEndpoint {payload endpoint} {
    if {[llength $endpoint]==1 && [dict exists $payload junctions $endpoint]} {return [dict get $payload junctions $endpoint]}
    if {[llength $endpoint]!=2} {error {Endpoint requires a junction ID or component/pin ID pair}}
    lassign $endpoint component pin
    set item [dict get $payload components $component]
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    lassign [dict get $catalog symbols [dict get $item kind] pins $pin] x y
    # Exact quarter turns of display coordinates, not scientific computation.
    switch [dict get $item rotation] {90 {lassign [list [expr {-$y}] $x] x y} 180 {set x [expr {-$x}];set y [expr {-$y}]} 270 {lassign [list $y [expr {-$x}]] x y}}
    lassign [dict get $item position] px py
    return [list [expr {$px+$x}] [expr {$py+$y}]]
}
proc ::GX::native2DGeometryDiagramCreate {module provider catalog} {
    native2DGeometryDiagramCatalog $catalog
    set payload [dict create schema gxtxt.native2d.diagram.v1 catalog $catalog next_id 1 components {} junctions {} wires {} labels {}]
    return [interactiveDocumentCreate $module $provider gxtxt.native2d.diagram.v1 1 $payload]
}
proc ::GX::native2DGeometryDiagramRead {document} {
    set result [interactiveDocumentRead $document]
    if {[dict get $result format] ne {gxtxt.native2d.diagram.v1} || [dict get $result format_version]!=1} {error {Document is not a compatible Native2D diagram}}
    native2DGeometryDiagramValidate [dict get $result payload]
    return $result
}
proc ::GX::native2DGeometryDiagramEdit {document expected operation request {mode commit}} {
    if {$mode ni {commit preview}} {error {Diagram edit mode must be commit or preview}}
    set owner [native2DGeometryDiagramRead $document]
    foreach key {generation revision sha256} {if {![dict exists $expected $key] || [dict get $expected $key] ne [dict get $owner $key]} {return -code error -errorcode {GX NATIVE2D STALE_SOURCE} {Diagram owner/revision changed; refresh before editing}}}
    set payload [dict get $owner payload]
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    set id [datasetPublicationV2DictDefault $request id {}]
    set allowed [dict get {place {kind name position rotation attributes} junction {position} wire {start end route} label {id endpoint text offset} properties {id name attributes} transform {id position rotation} route {id route start end} remove {id} restore {payload}} $operation]
    foreach key [dict keys $request] {if {$key ni $allowed} {error "Unsupported diagram '$operation' field '$key'"}}
    switch $operation {
        place {
            set kind [dict get $request kind];set symbol [dict get $catalog symbols $kind]
            set n [dict get $payload next_id];dict incr payload next_id
            set id component_$n
            set name [datasetPublicationV2DictDefault $request name [dict get $symbol prefix]$n]
            dict set payload components $id [dict create kind $kind name $name position [dict get $request position] rotation [datasetPublicationV2DictDefault $request rotation 0] attributes [_native2DDiagramAttributes $symbol [datasetPublicationV2DictDefault $request attributes {}]]]
        }
        junction {
            set n [dict get $payload next_id];dict incr payload next_id;set id junction_$n
            dict set payload junctions $id [dict get $request position]
        }
        wire {
            set n [dict get $payload next_id];dict incr payload next_id;set id wire_$n
            dict set payload wires $id [dict create start [dict get $request start] end [dict get $request end] route [datasetPublicationV2DictDefault $request route {}]]
        }
        label {
            if {$id eq {}} {
                set n [dict get $payload next_id];dict incr payload next_id;set id label_$n
                set item [dict create endpoint [dict get $request endpoint] text [dict get $request text] offset {5 12}]
            } else {
                if {![dict exists $payload labels $id]} {error {Select an existing net label}}
                set item [dict get $payload labels $id]
            }
            foreach key {endpoint text offset} {if {[dict exists $request $key]} {dict set item $key [dict get $request $key]}}
            dict set payload labels $id $item
        }
        properties {
            set item [dict get $payload components $id]
            foreach key [dict keys $request] {if {$key ni {id name attributes}} {error {Unsupported symbol property}}}
            if {[dict exists $request name]} {dict set item name [dict get $request name]}
            if {[dict exists $request attributes]} {dict set item attributes [_native2DDiagramAttributes [dict get $catalog symbols [dict get $item kind]] [dict merge [dict get $item attributes] [dict get $request attributes]]]}
            dict set payload components $id $item
        }
        transform {
            set item [dict get $payload components $id]
            foreach key [dict keys $request] {if {$key ni {id position rotation}} {error {Unsupported symbol transform}}}
            foreach key {position rotation} {if {[dict exists $request $key]} {dict set item $key [dict get $request $key]}}
            dict set payload components $id $item
        }
        route {
            if {![dict exists $payload wires $id]} {error {Select an existing wire}}
            if {![dict exists $request route] && ![dict exists $request start] && ![dict exists $request end]} {error {Wire edit requires route or endpoints}}
            set wire [dict get $payload wires $id]
            foreach key {route start end} {if {[dict exists $request $key]} {dict set wire $key [dict get $request $key]}}
            dict set payload wires $id $wire
        }
        remove {
            set found 0
            foreach collection {components junctions wires labels} {if {[dict exists $payload $collection $id]} {dict unset payload $collection $id;set found 1;break}}
            if {!$found} {error {Unknown diagram object}}
            # Removing a terminal removes only its explicit incident connections.
            dict for {wire entry} [dict get $payload wires] {if {[lindex [dict get $entry start] 0] eq $id || [lindex [dict get $entry end] 0] eq $id} {dict unset payload wires $wire}}
            dict for {label entry} [dict get $payload labels] {if {[lindex [dict get $entry endpoint] 0] eq $id} {dict unset payload labels $label}}
        }
        restore {
            set restored [dict get $request payload]
            if {[dict get $restored catalog] ne [dict get $payload catalog]} {error {History restoration cannot replace the symbol catalog}}
            dict set restored next_id [expr {max([dict get $payload next_id],[dict get $restored next_id])}]
            set payload $restored
        }
        default {error {Unsupported public diagram edit operation}}
    }
    native2DGeometryDiagramValidate $payload
    if {$mode eq {preview}} {
        # The same candidate/semantic validator, without allocating an ID or
        # updating the canonical document. Callers must revalidate on commit.
        return [dict create status VALIDATED source [dict remove $owner payload] object_id $id operation $operation proposed_payload $payload]
    }
    # No event dispatch or external process occurs between comparison and commit.
    set updated [interactiveDocumentUpdate $document $payload]
    return [dict create document $updated object_id $id operation $operation payload $payload]
}
proc ::GX::native2DGeometryDiagramProject {document} {
    set owner [native2DGeometryDiagramRead $document]
    set payload [dict get $owner payload]
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    set token [native2DGeometryOpen $document]
    set map {};set annotations {}
    try {
        dict for {id item} [dict get $payload components] {
            set symbol [dict get $catalog symbols [dict get $item kind]]
            set parts {}
            foreach path [dict get $symbol paths] {lappend parts [dict get [native2DGeometryCall $token curve [dict create points $path]] object_token]}
            set native [dict get [_native2DGeometryRequire $token] native]
            set matrix [::GX::Native2D::core rotation_matrix_degrees $native {0 0} [dict get $item rotation]]
            native2DGeometryCall $token affine [dict create object_tokens $parts matrix $matrix]
            lassign [dict get $item position] x y
            native2DGeometryCall $token affine [dict create object_tokens $parts matrix [list 1 0 0 1 $x $y]]
            foreach part $parts {native2DGeometryCall $token style [dict create object_token $part properties {color {0.12 0.22 0.38 1} line_width 2 marker 0}]}
            dict set map $id $parts
            set text [dict get $item name]
            if {[dict exists $item attributes value]} {append text " · [dict get $item attributes value] [datasetPublicationV2DictDefault [dict get $symbol attributes value] unit {}]"}
            if {[dict exists $item attributes caption]} {append text " · [dict get $item attributes caption]"}
            lappend annotations [dict create point [list $x [expr {$y+30}]] text $text anchor s]
        }
        dict for {id wire} [dict get $payload wires] {
            set start [native2DGeometryDiagramEndpoint $payload [dict get $wire start]]
            set end [native2DGeometryDiagramEndpoint $payload [dict get $wire end]]
            set route [dict get $wire route]
            if {$route eq {}} {set route [list [list [lindex $end 0] [lindex $start 1]]]}
            set object [dict get [native2DGeometryCall $token curve [dict create points [list $start {*}$route $end]]] object_token]
            native2DGeometryCall $token style [dict create object_token $object properties {color {0.05 0.45 0.25 1} line_width 2 marker 0}]
            dict set map $id [list $object]
        }
        dict for {id point} [dict get $payload junctions] {
            set object [dict get [native2DGeometryCall $token curve [dict create kind pointset points [list $point]]] object_token]
            native2DGeometryCall $token style [dict create object_token $object properties {color {0.05 0.45 0.25 1} marker 1 line_width 3}]
            dict set map $id [list $object]
        }
        dict for {id label} [dict get $payload labels] {
            lassign [native2DGeometryDiagramEndpoint $payload [dict get $label endpoint]] x y
            lassign [datasetPublicationV2DictDefault $label offset {0 0}] dx dy
            lappend annotations [dict create id $id point [list [expr {$x+$dx}] [expr {$y+$dy}]] text [dict get $label text] anchor sw]
        }
        native2DGeometryCall $token fit_bounds {bounds {-120 -100 240 180}}
        return [dict create scene_token $token document [dict remove $owner payload] object_tokens $map annotations $annotations]
    } on error {message options} {native2DGeometryClose $token;return -options $options $message}
}
# Trusted built-in data resources, read as inert dictionaries, never sourced.
set ::GX::Native2DDiagram::catalogResource [file join [file dirname [info script]] .. assets diagrams catalogs.tcldict]
set ::GX::Native2DDiagram::catalogChannel [open $::GX::Native2DDiagram::catalogResource r]
try {
    dict for {id descriptor} [read $::GX::Native2DDiagram::catalogChannel 131073] {::GX::native2DGeometryDiagramCatalogRegister $id $descriptor}
} finally {close $::GX::Native2DDiagram::catalogChannel;unset ::GX::Native2DDiagram::catalogChannel}
