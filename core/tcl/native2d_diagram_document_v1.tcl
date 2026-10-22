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
        set pathSets [list [dict get $symbol paths]]
        if {[dict exists $symbol variants]} {
            set variants [dict get $symbol variants];set attribute [dict get $variants attribute]
            if {![dict exists $symbol attributes $attribute] || [dict get $symbol attributes $attribute type] ne {choice} || [dict size [dict get $variants marks]]>16} {error {Symbol variants require a bounded declared choice attribute}}
            dict for {choice paths} [dict get $variants marks] {
                if {$choice ni [dict get $symbol attributes $attribute values]} {error {Symbol variant is outside its attribute choices}}
                lappend pathSets $paths
            }
        }
        foreach paths $pathSets {
            if {[llength $paths]>32} {error {Symbol variant exceeds 32 paths}}
            foreach path $paths {
                if {[llength $path]<2 || [llength $path]>128} {error {Symbol path requires 2..128 vertices}}
                foreach point $path {_native2DDiagramPoint $point}
            }
        }
        dict for {pin point} [dict get $symbol pins] {_native2DDiagramId $pin;_native2DDiagramPoint $point}
        dict for {attribute field} [dict get $symbol attributes] {
            _native2DDiagramId $attribute
            if {![dict exists $field type] || [dict get $field type] ni {number string choice} || ![dict exists $field default]} {error {Symbol attribute requires typed default}}
            if {$id eq {electrical.basic} && [dict get $field type] eq {number}} {
                dict set descriptor symbols $kind attributes $attribute notation electrical_engineering
            }
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
proc ::GX::_native2DDiagramElectricalNumber {value} {
    set value [string trim $value]
    if {[string is double -strict $value]} {return $value}
    if {![regexp -nocase {^([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:e[+-]?[0-9]+)?)(meg|[tgkmunpfµμ])$} $value -> number suffix]} {
        error {Enter a finite SI number or an engineering value such as 4.7k, 470n or 1meg (m means milli; meg means mega).}
    }
    set exponent [dict get {t 12 g 9 meg 6 k 3 m -3 u -6 µ -6 μ -6 n -9 p -12 f -15} [string tolower $suffix]]
    lassign [split [string tolower $number] e] mantissa suppliedExponent
    if {$suppliedExponent ne {}} {scan $suppliedExponent %d suppliedExponent;incr exponent $suppliedExponent}
    # Parse the combined decimal exponent once rather than rounding a parsed
    # mantissa and then multiplying it by another rounded floating point value.
    set result [expr {double("${mantissa}e${exponent}")}]
    if {abs($result)>=Inf || ($result==0 && double($number)!=0)} {error {Engineering value is outside the finite SI range}}
    return $result
}
proc ::GX::_native2DDiagramElectricalDisplay {value} {
    # Presentation only. An editable engineering string must round-trip to the
    # identical double; fall back to its full SI representation otherwise.
    if {$value==0} {return 0}
    foreach {exponent suffix} {12 t 9 g 6 meg 3 k 0 {} -3 m -6 u -9 n -12 p -15 f} {
        if {abs(double($value))<pow(10.0,$exponent)} continue
        set scaled [expr {double($value)/pow(10.0,$exponent)}]
        foreach digits {12 17} {
            set candidate [format %.*g $digits $scaled]$suffix
            if {![catch {_native2DDiagramElectricalNumber $candidate} parsed] && $parsed==$value} {return $candidate}
        }
        break
    }
    return [format %.17g $value]
}
proc ::GX::_native2DDiagramAttributeNormalize {field value} {
    if {[datasetPublicationV2DictDefault $field notation {}] eq {electrical_engineering}} {set value [_native2DDiagramElectricalNumber $value]}
    if {[dict get $field type] eq {number}} {
        if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {error {Electrical attribute requires a finite numeric SI value}}
        foreach {bound relation} {min < max >} {
            if {[dict exists $field $bound] && [expr "$value $relation [dict get $field $bound]"]} {error "Attribute violates $bound"}
        }
    } elseif {[dict get $field type] eq {choice} && $value ni [dict get $field values]} {error {Attribute is outside catalog choices}}
    return $value
}
proc ::GX::_native2DDiagramAttributes {symbol attributes} {
    set schema [dict get $symbol attributes];set result {}
    dict for {key value} $attributes {if {![dict exists $schema $key]} {error "Unknown symbol attribute '$key'"}}
    dict for {key field} $schema {
        set value [datasetPublicationV2DictDefault $attributes $key [dict get $field default]]
        if {[string bytelength $value]>256 || [regexp {[\x00\r\n]} $value]} {error {Diagram attribute exceeds single-line text bounds}}
        dict set result $key [_native2DDiagramAttributeNormalize $field $value]
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
        dict for {attribute field} [dict get $symbol attributes] {
            if {[dict get $field type] eq {number} && [dict exists $item attributes $attribute] && ![string is double -strict [dict get $item attributes $attribute]]} {error {Canonical diagram numeric attributes must contain SI numbers, not suffix strings}}
        }
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
proc ::GX::_native2DDiagramWirePoints {payload wire} {
    set start [native2DGeometryDiagramEndpoint $payload [dict get $wire start]]
    set end [native2DGeometryDiagramEndpoint $payload [dict get $wire end]]
    set route [dict get $wire route]
    if {$route eq {}} {set route [list [list [lindex $end 0] [lindex $start 1]]]}
    return [list $start {*}$route $end]
}
proc ::GX::_native2DDiagramIsWireTarget {target} {
    return [expr {[llength $target]==6 && [dict exists $target kind] && [dict get $target kind] eq {wire} && [lsort [dict keys $target]] eq {kind point wire_id}}]
}
proc ::GX::_native2DDiagramTargetPoint {payload target} {
    if {[_native2DDiagramIsWireTarget $target]} {return [_native2DDiagramPoint [dict get $target point]]}
    return [native2DGeometryDiagramEndpoint $payload $target]
}
proc ::GX::_native2DDiagramSamePoint {a b} {
    return [expr {[lindex $a 0]==[lindex $b 0] && [lindex $a 1]==[lindex $b 1]}]
}
proc ::GX::_native2DDiagramAllocate {payloadVariable prefix} {
    upvar 1 $payloadVariable payload
    while {1} {
        set n [dict get $payload next_id];dict incr payload next_id;set id ${prefix}_$n;set occupied 0
        foreach collection {components junctions wires labels} {if {[dict exists $payload $collection $id]} {set occupied 1;break}}
        if {!$occupied} {return [list $id $n]}
    }
}
proc ::GX::_native2DDiagramWireTargets {payload targets} {
    # Resolve all intentional attachments against the SAME original payload.
    # The existing C kernel owns segment projection; this owner only splits
    # canonical endpoint references in one document/History transaction.
    set groups {};set resolved {};set scene {};set index -1
    try {
        foreach target $targets {
            incr index
            if {![_native2DDiagramIsWireTarget $target]} {
                native2DGeometryDiagramEndpoint $payload $target
                dict set resolved $index $target
                continue
            }
            set wireId [dict get $target wire_id];set wire [dict get $payload wires $wireId]
            set points [_native2DDiagramWirePoints $payload $wire]
            if {$scene eq {}} {native2DEnsure;set scene [::GX::Native2D::core scene]}
            set object [::GX::Native2D::core add $scene $points]
            set hit [::GX::Native2D::core nearest_segment $scene $object [_native2DDiagramPoint [dict get $target point]]]
            ::GX::Native2D::core delete $scene $object
            if {[dict get $hit distance]>1e-7} {error {Wire attachment no longer lies on the selected segment}}
            set point [dict get $hit point]
            if {[_native2DDiagramSamePoint $point [lindex $points 0]]} {dict set resolved $index [dict get $wire start];continue}
            if {[_native2DDiagramSamePoint $point [lindex $points end]]} {dict set resolved $index [dict get $wire end];continue}
            set junction {}
            foreach cut [datasetPublicationV2DictDefault $groups $wireId {}] {
                if {[_native2DDiagramSamePoint $point [lindex $cut 3]]} {set junction [lindex $cut 2];break}
            }
            if {$junction eq {}} {
                lassign [_native2DDiagramAllocate payload junction] junction n
                dict set payload junctions $junction $point
                dict lappend groups $wireId [list [dict get $hit segment] [dict get $hit t] $junction $point]
            }
            dict set resolved $index $junction
        }
        dict for {wireId cuts} $groups {
            set wire [dict get $payload wires $wireId]
            set points [_native2DDiagramWirePoints $payload $wire]
            set start [dict get $wire start];set part [list [lindex $points 0]];set pieces {}
            set cuts [lsort -real -index 1 $cuts]
            for {set segment 0} {$segment<[llength $points]-1} {incr segment} {
                foreach cut $cuts {
                    if {[lindex $cut 0]!=$segment} continue
                    lassign $cut unused fraction end point
                    if {![_native2DDiagramSamePoint $point [lindex $part end]]} {lappend part $point}
                    set route [lrange $part 1 end-1]
                    # A nonempty explicit route preserves a diagonal straight
                    # segment instead of invoking the empty-route elbow default.
                    if {$route eq {}} {set route [list [lindex $part 0]]}
                    lappend pieces [dict create start $start end $end route $route]
                    set start $end;set part [list $point]
                }
                set point [lindex $points [expr {$segment+1}]]
                if {![_native2DDiagramSamePoint $point [lindex $part end]]} {lappend part $point}
            }
            set route [lrange $part 1 end-1]
            if {$route eq {}} {set route [list [lindex $part 0]]}
            lappend pieces [dict create start $start end [dict get $wire end] route $route]
            set first 1
            foreach piece $pieces {
                if {$first} {set id $wireId;set first 0} else {lassign [_native2DDiagramAllocate payload wire] id n}
                dict set payload wires $id $piece
            }
        }
    } finally {if {$scene ne {}} {::GX::Native2D::core destroy $scene}}
    set endpoints {}
    for {set i 0} {$i<[llength $targets]} {incr i} {lappend endpoints [dict get $resolved $i]}
    return [list $payload $endpoints]
}
proc ::GX::_native2DDiagramJunctionTargets {payload targets} {
    if {![llength $targets] || [llength $targets]>1024} {error {Intentional junction requires 1..1024 electrical targets}}
    set point [_native2DDiagramTargetPoint $payload [lindex $targets 0]]
    foreach target $targets {
        if {![_native2DDiagramSamePoint $point [_native2DDiagramTargetPoint $payload $target]]} {error {Intentional junction targets must share one location}}
    }
    set original [dict get $payload junctions]
    lassign [_native2DDiagramWireTargets $payload $targets] payload endpoints
    # Target picking order does not change an already intentional junction.
    set endpoints [lsort -unique $endpoints]
    set common [lindex $endpoints 0]
    foreach endpoint $endpoints {
        if {[llength $endpoint]==2 || [dict exists $original $endpoint]} {set common $endpoint;break}
    }
    foreach endpoint [lsort -unique $endpoints] {
        if {$endpoint eq $common} continue
        if {[llength $endpoint]==1 && [dict exists $payload junctions $endpoint] && ![dict exists $original $endpoint]} {
            # Coalesce only junctions created by this transaction. Existing
            # junction/component identities survive an intentional net join.
            dict for {id wire} [dict get $payload wires] {
                foreach side {start end} {if {[dict get $wire $side] eq $endpoint} {dict set wire $side $common}}
                dict set payload wires $id $wire
            }
            dict unset payload junctions $endpoint
        } else {
            # Repeating an intentional join must reuse its existing canonical
            # connection rather than manufacture another zero-length wire.
            set joined 0
            dict for {id wire} [dict get $payload wires] {
                set a [dict get $wire start];set b [dict get $wire end]
                if {($a eq $common && $b eq $endpoint) || ($b eq $common && $a eq $endpoint)} {set joined 1;break}
            }
            if {$joined} continue
            lassign [_native2DDiagramAllocate payload wire] id n
            dict set payload wires $id [dict create start $common end $endpoint route [list $point]]
        }
    }
    return [list $payload $common]
}
proc ::GX::native2DGeometryDiagramEdit {document expected operation request {mode commit}} {
    if {$mode ni {commit preview}} {error {Diagram edit mode must be commit or preview}}
    set owner [native2DGeometryDiagramRead $document]
    foreach key {generation revision sha256} {if {![dict exists $expected $key] || [dict get $expected $key] ne [dict get $owner $key]} {return -code error -errorcode {GX NATIVE2D STALE_SOURCE} {Diagram owner/revision changed; refresh before editing}}}
    set payload [dict get $owner payload]
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    set id [datasetPublicationV2DictDefault $request id {}]
    set allowed [dict get {place {kind name position rotation attributes} junction {position target targets} wire {start end route} label {id endpoint text offset} properties {id name attributes} transform {id position rotation} route {id route start end} remove {id} restore {payload}} $operation]
    foreach key [dict keys $request] {if {$key ni $allowed} {error "Unsupported diagram '$operation' field '$key'"}}
    switch $operation {
        place {
            set kind [dict get $request kind];set symbol [dict get $catalog symbols $kind]
            lassign [_native2DDiagramAllocate payload component] id n
            set name [datasetPublicationV2DictDefault $request name [dict get $symbol prefix]$n]
            dict set payload components $id [dict create kind $kind name $name position [dict get $request position] rotation [datasetPublicationV2DictDefault $request rotation 0] attributes [_native2DDiagramAttributes $symbol [datasetPublicationV2DictDefault $request attributes {}]]]
        }
        junction {
            if {[dict exists $request targets]} {
                lassign [_native2DDiagramJunctionTargets $payload [dict get $request targets]] payload endpoint
                set id [lindex $endpoint 0]
            } elseif {[dict exists $request target]} {
                lassign [_native2DDiagramWireTargets $payload [list [dict get $request target]]] payload endpoints
                set id [lindex [lindex $endpoints 0] 0]
            } else {
                lassign [_native2DDiagramAllocate payload junction] id n
                dict set payload junctions $id [dict get $request position]
            }
        }
        wire {
            lassign [_native2DDiagramWireTargets $payload [list [dict get $request start] [dict get $request end]]] payload endpoints
            lassign [_native2DDiagramAllocate payload wire] id n
            dict set payload wires $id [dict create start [lindex $endpoints 0] end [lindex $endpoints 1] route [datasetPublicationV2DictDefault $request route {}]]
        }
        label {
            if {[dict exists $request endpoint] && [_native2DDiagramIsWireTarget [dict get $request endpoint]]} {
                # Validate the same canonical segment target before resolving
                # its net. The temporary split candidate is deliberately not
                # committed: a net label needs no additional electrical node.
                _native2DDiagramWireTargets $payload [list [dict get $request endpoint]]
                dict set request endpoint [dict get $payload wires [dict get $request endpoint wire_id] start]
            }
            if {$id eq {}} {
                lassign [_native2DDiagramAllocate payload label] id n
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
proc ::GX::native2DGeometryDiagramProject {document {preview {}}} {
    set owner [native2DGeometryDiagramRead $document]
    set payload [dict get $owner payload]
    if {$preview ne {}} {
        if {[dict get $preview status] ne {VALIDATED}} {error {A validated diagram preview is required}}
        foreach field {id generation revision sha256} {
            if {[dict get $owner $field] ne [dict get $preview source $field]} {return -code error -errorcode {GX NATIVE2D STALE_SOURCE} {Diagram changed during transient presentation}}
        }
        set payload [dict get $preview proposed_payload]
        native2DGeometryDiagramValidate $payload
        if {[dict get $payload catalog] ne [dict get $owner payload catalog]} {error {A preview cannot replace its diagram catalog}}
    }
    set catalog [native2DGeometryDiagramCatalog [dict get $payload catalog]]
    set token [native2DGeometryOpen $document]
    set map {};set annotations {}
    try {
        dict for {id item} [dict get $payload components] {
            set symbol [dict get $catalog symbols [dict get $item kind]]
            set parts {}
            set paths [dict get $symbol paths]
            if {[dict exists $symbol variants]} {
                set variants [dict get $symbol variants];set attribute [dict get $variants attribute]
                set choice [datasetPublicationV2DictDefault [dict get $item attributes] $attribute [dict get $symbol attributes $attribute default]]
                if {[dict exists $variants marks $choice]} {lappend paths {*}[dict get $variants marks $choice]}
            }
            foreach path $paths {lappend parts [dict get [native2DGeometryCall $token curve [dict create points $path]] object_token]}
            set native [dict get [_native2DGeometryRequire $token] native]
            set matrix [::GX::Native2D::core rotation_matrix_degrees $native {0 0} [dict get $item rotation]]
            native2DGeometryCall $token affine [dict create object_tokens $parts matrix $matrix]
            lassign [dict get $item position] x y
            native2DGeometryCall $token affine [dict create object_tokens $parts matrix [list 1 0 0 1 $x $y]]
            foreach part $parts {native2DGeometryCall $token style [dict create object_token $part properties {color {0.12 0.22 0.38 1} line_width 2 marker 0}]}
            dict set map $id $parts
            set text [dict get $item name]
            if {[dict exists $item attributes value]} {
                set value [dict get $item attributes value]
                if {[datasetPublicationV2DictDefault [dict get $symbol attributes value] notation {}] eq {electrical_engineering}} {set value [_native2DDiagramElectricalDisplay $value]}
                append text " · $value [datasetPublicationV2DictDefault [dict get $symbol attributes value] unit {}]"
            }
            if {[dict exists $item attributes caption]} {append text " · [dict get $item attributes caption]"}
            lappend annotations [dict create id $id point [list $x [expr {$y+30}]] text $text anchor s]
        }
        dict for {id wire} [dict get $payload wires] {
            set object [dict get [native2DGeometryCall $token curve [dict create points [_native2DDiagramWirePoints $payload $wire]]] object_token]
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
