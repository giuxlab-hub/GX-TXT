# SPDX-License-Identifier: GPL-3.0-or-later
# One bounded source/semantic owner. No evaluator, external renderer, registry,
# pathname resolution, canonical publication or GUI is entered by parsing.
namespace eval ::GX::UmlV1 {variable profile gxtxt.plantuml.v1;variable version 1}
proc ::GX::umlDocumentApiInfo {} {
    return [dict create api_id UML_DOCUMENT_API_v1 api_version 1 owner CORE \
        profile gxtxt.plantuml.v1 notation {PlantUML-compatible GX-TXT subset} \
        families {class sequence} deferred_families {use_case activity state} \
        source_bytes_max 4194304 class_elements_max 256 class_relations_max 1024 \
        participants_max 64 messages_max 2048 frame_depth_max 8 \
        operations {umlDocumentDetect umlDocumentParse umlDocumentEdit umlDocumentLayout umlDocumentInspectElement umlDocumentDescribe umlDocumentRead umlDocumentWrite umlDocumentExport umlDocumentExportRelease} \
        commands {umlDocumentDetect umlDocumentParse umlDocumentEdit umlDocumentLayout umlDocumentInspectElement umlDocumentDescribe umlDocumentRead umlDocumentWrite umlDocumentExport umlDocumentExportRelease} \
        host_operations {umlDiagramMount umlDiagramCommand umlEditorMount umlEditorCommand} export_formats {source png svg} export_pixels_max 16777216 \
        unsupported {preprocessor includes macros network HTML XMI Mermaid full_PlantUML full_UML_compliance} \
        source_authority exact_UTF8 model_authority derived_source_SHA]
}
proc ::GX::_umlDigest {text} {
    documentNativeEnsure
    return [::GX::NativeDocument::snapshotCache digest [encoding convertto utf-8 $text]]
}
proc ::GX::_umlDiagnostic {line code message {column 1}} {
    return [dict create severity error line $line column $column code $code message $message]
}
proc ::GX::_umlFail {line code message} {return -code error -errorcode [list GX UML $line $code] $message}
proc ::GX::_umlLabel {label line} {
    if {$label eq {} || [string length $label]>512 || [regexp {[\x00-\x1f\x7f"\\<>]} $label]} {_umlFail $line LABEL {Labels need 1..512 plain characters; markup, escapes and control characters are unsupported}}
    return $label
}
proc ::GX::_umlAlias {alias line} {
    if {![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $alias]} {_umlFail $line ALIAS {Use a stable ASCII alias of at most 64 characters; Unicode display names use quotes and as}}
    return $alias
}
proc ::GX::_umlMultiplicity {value line} {
    if {$value eq {}} {return {}}
    if {![regexp {^(\*|[0-9]+(\.\.([0-9]+|\*))?)$} $value]} {_umlFail $line MULTIPLICITY {Multiplicity must be *, n, n..m or n..*}}
    if {[regexp {^([0-9]+)\.\.([0-9]+)$} $value -> a b] && $a>$b} {_umlFail $line MULTIPLICITY {Multiplicity lower bound exceeds its upper bound}}
    return $value
}
proc ::GX::umlDocumentDetect {filename source} {
    set candidate [expr {[string tolower [file extension $filename]] in {.puml .plantuml}}]
    if {!$candidate} {return [dict create schema gxtxt.uml.detection.v1 candidate 0 recognized 0 diagnostics {}]}
    set parsed [umlDocumentParse $source]
    return [dict create schema gxtxt.uml.detection.v1 candidate 1 recognized [dict get $parsed valid] \
        contract document.uml format puml media_type text/vnd.plantuml profile gxtxt.plantuml.v1 \
        parser_version 1 family [dict get $parsed family] source_sha256 [dict get $parsed source_sha256] diagnostics [dict get $parsed diagnostics]]
}
proc ::GX::_umlItemId {text prefix pending countsVar} {
    upvar 1 $countsVar counts
    if {$pending ne {}} {return $pending}
    set hash [string range [_umlDigest $text] 0 15]
    set base ${prefix}_$hash
    set count [expr {[dict exists $counts $base] ? [dict get $counts $base]+1 : 1}]
    dict set counts $base $count
    return ${base}_$count
}
proc ::GX::umlDocumentParse {source {options {}}} {
    if {[catch {dict size $options}]} {error {UML parse options must be a dictionary}}
    foreach k [dict keys $options] {if {$k ni {profile family}} {error "Unknown UML parse option: $k"}}
    set profile [datasetPublicationV2DictDefault $options profile gxtxt.plantuml.v1]
    set expected [datasetPublicationV2DictDefault $options family auto]
    if {$profile ne {gxtxt.plantuml.v1} || $expected ni {auto class sequence}} {error {Choose the supported gxtxt.plantuml.v1 class/sequence profile}}
    set bytes [encoding convertto utf-8 $source]
    if {[string length $bytes]>4194304 || [string first \x00 $source]>=0} {error {UML source must be UTF-8 without NUL and at most 4 MiB}}
    documentUtf8Prefix $bytes [string length $bytes]
    set receipt [dict create schema gxtxt.uml.parse.v1 parser_version 1 profile $profile source $source source_sha256 [_umlDigest $source] source_bytes [string length $bytes] valid 0 family {} title {} elements {} relations {} messages {} frames {} positions {} diagnostics {}]
    try {
        _umlParseSource $source $expected receipt
        dict set receipt valid 1
    } on error {message opts} {
        set code [dict get $opts -errorcode]
        if {[lrange $code 0 1] ne {GX UML}} {return -options $opts $message}
        dict set receipt diagnostics [list [_umlDiagnostic [lindex $code 2] [lindex $code 3] $message]]
    }
    return $receipt
}
proc ::GX::_umlParseSource {source expected resultVar} {
    upvar 1 $resultVar result
    set offset 0;set number 0;set opened 0;set ended 0;set blockComment 0
    set family {};set elements {};set relations {};set messages {};set frames {};set positions {};set stack {}
    set owner {};set pending {};set pendingStart {};set counts {};set seenIds {};set title {}
    foreach raw [split $source \n] {
        incr number
        if {$number>20000 || [string length $raw]>8192} {_umlFail $number LIMIT {UML supports at most 20000 lines and 8192 characters per line}}
        set start $offset;set end [expr {min([string length $source],$start+[string length $raw]+1)}];set offset $end
        set line [string trim $raw];if {$number==1} {set line [string trimleft $line \ufeff]}
        if {$blockComment} {if {[string first "'/" $line]>=0} {set blockComment 0};continue}
        if {[string match {/'*} $line]} {if {[string first "'/" [string range $line 2 end]]<0} {set blockComment 1};continue}
        if {$line eq {}} continue
        if {[regexp {^'\s*@gx-id\s+([A-Za-z_][A-Za-z0-9_]{0,63})\s*$} $line -> id]} {
            if {$pending ne {} || [dict exists $seenIds $id]} {_umlFail $number ID {Duplicate or unattached editor identity annotation}}
            set pending $id;set pendingStart $start;continue
        }
        if {[regexp {^'\s*@gx-position\s+([A-Za-z_][A-Za-z0-9_]{0,63})\s+(-?[0-9]+(?:\.[0-9]+)?)\s+(-?[0-9]+(?:\.[0-9]+)?)\s*$} $line -> alias x y]} {
            if {abs($x)>50000 || abs($y)>50000 || [dict exists $positions $alias]} {_umlFail $number POSITION {Duplicate or out-of-range element position}}
            dict set positions $alias [dict create x $x y $y span [list $start $end] line $number];continue
        }
        if {[regexp {^'\s*@gx-family\s+(class|sequence)\s*$} $line -> declared]} {
            if {$family ne {} && $family ne $declared} {_umlFail $number FAMILY {Family annotation contradicts actual diagram constructs}}
            set family $declared;continue
        }
        if {[string index $line 0] eq {'}} continue
        if {$ended} {_umlFail $number END {Content after @enduml is unsupported}}
        if {!$opened} {
            if {$line ne {@startuml}} {_umlFail $number START {Begin this profile with @startuml}}
            set opened 1;continue
        }
        if {$line eq {@enduml}} {
            if {$owner ne {} || [llength $stack]} {_umlFail $number UNCLOSED {Close class bodies and sequence frames before @enduml}}
            set ended 1;dict set result end_span [list $start $end];continue
        }
        if {[regexp {^title\s+(.+)$} $line -> label]} {
            if {$title ne {} || $owner ne {} || $pending ne {}} {_umlFail $number TITLE {Use one top-level title}}
            set title [_umlLabel $label $number];continue
        }
        set span [list $start $end];set annotatedSpan [list [expr {$pendingStart eq {}?$start:$pendingStart}] $end]
        if {$owner ne {}} {
            if {$line eq "\u007d"} {
                if {$pending ne {}} {_umlFail $number ID {Identity annotation must precede a semantic item}}
                dict set elements $owner close_span $span
                dict set elements $owner span [list [lindex [dict get $elements $owner span] 0] $end]
                set owner {};continue
            }
            if {[regexp {[{}!<>]} $line] || [string length $line]>512} {_umlFail $number MEMBER {Unsupported class member syntax or markup}}
            set visibility {};set body $line
            if {[regexp {^([+\-#~])\s*(.+)$} $line -> visibility body]==0 && [regexp {^[+\-#~]$} $line]} {_umlFail $number MEMBER {A visibility marker needs a member}}
            set kind [expr {[string first ( $body]>=0 ? {operation}:{attribute}}]
            if {$kind eq {operation} && ![regexp {^[^()]+\([^()]*\)[^()]*$} $body]} {_umlFail $number MEMBER {Operation members need one balanced parameter list}}
            set id [_umlItemId $line member $pending counts]
            if {[dict exists $seenIds $id]} {_umlFail $number ID {Semantic identity is duplicated}}
            dict set seenIds $id 1
            set element [dict get $elements $owner]
            dict lappend element members [dict create id $id kind $kind text $body visibility $visibility line $number span $span annotated_span $annotatedSpan]
            dict set elements $owner $element
            set pending {};set pendingStart {};continue
        }
        if {[regexp {^(class|interface|participant|actor)\s+(?:"([^"\r\n]+)"\s+as\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(\{)?\s*$} $line -> type label alias brace]} {
            set candidate [expr {$type in {class interface}?{class}:{sequence}}]
            if {$family ne {} && $candidate ne $family} {_umlFail $number FAMILY {Class and sequence constructs cannot share one diagram}}
            set family $candidate
            if {$brace ne {} && $family ne {class}} {_umlFail $number BODY {Participant bodies are outside this profile}}
            _umlAlias $alias $number
            if {$label eq {}} {set label $alias};_umlLabel $label $number
            if {[dict exists $elements $alias] || [dict exists $seenIds $alias]} {_umlFail $number ALIAS {Element alias is duplicated}}
            if {$pending ne {} && $pending ne $alias} {_umlFail $number ID {Element identity is its stable declared alias}}
            dict set seenIds $alias 1
            dict set elements $alias [dict create id $alias type $type name $label members {} line $number span $span declaration_span $span annotated_span $annotatedSpan close_span {}]
            if {$brace ne {}} {set owner $alias}
            if {[dict size $elements]>[expr {$family eq {class}?256:64}]} {_umlFail $number LIMIT {Diagram element bound exceeded}}
            set pending {};set pendingStart {};continue
        }
        if {[regexp {^([A-Za-z_][A-Za-z0-9_]*)\s*(?:"([^"\r\n]+)"\s*)?(<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|-->|<--|\.\.>|<\.\.|--)\s*(?:"([^"\r\n]+)"\s*)?([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*(.+))?\s*$} $line -> from left arrow right to label] && $family ne {sequence}} {
            if {$family eq {}} {set family class}
            if {$label ne {}} {_umlLabel $label $number}
            _umlMultiplicity $left $number;_umlMultiplicity $right $number
            set kind association;set marker end
            switch -- $arrow {
                <|-- {set kind generalization;set marker start}
                --|> {set kind generalization}
                <|.. {set kind realization;set marker start}
                ..|> {set kind realization}
                *-- {set kind composition;set marker start}
                --* {set kind composition}
                o-- {set kind aggregation;set marker start}
                --o {set kind aggregation}
                --> - <-- - ..> - <.. {set kind dependency;if {$arrow in {<-- <..}} {set marker start}}
            }
            set id [_umlItemId $line relation $pending counts]
            lappend relations [dict create id $id from $from to $to kind $kind arrow $arrow marker $marker left_multiplicity $left right_multiplicity $right label $label line $number span $span annotated_span $annotatedSpan]
            if {[llength $relations]>1024} {_umlFail $number LIMIT {At most 1024 class relationships are supported}}
        } elseif {[regexp {^([A-Za-z_][A-Za-z0-9_]*)\s*(->>|->|-->|<<-|<-|<--)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)$} $line -> from arrow to label]} {
            if {$family eq {class}} {_umlFail $number FAMILY {Sequence messages cannot share a class diagram}}
            set family sequence;_umlLabel $label $number
            set style sync
            if {$arrow in {->> <<-}} {set style async}
            if {$arrow in {--> <--}} {set style reply}
            if {$arrow in {<<- <- <--}} {set swap $from;set from $to;set to $swap}
            set id [_umlItemId $line message $pending counts]
            set context {};foreach frameId $stack {lappend context [list $frameId [llength [dict get $frames $frameId branches]]]}
            lappend messages [dict create id $id from $from to $to kind $style label $label order [llength $messages] frames $stack frame_context $context line $number span $span annotated_span $annotatedSpan]
            if {[llength $messages]>2048} {_umlFail $number LIMIT {At most 2048 sequence messages are supported}}
        } elseif {[regexp {^(alt|opt|loop)\s+(.+)$} $line -> type label]} {
            if {$family eq {class}} {_umlFail $number FAMILY {Control frames belong to sequence diagrams}}
            set family sequence;_umlLabel $label $number
            set id [_umlItemId $line frame $pending counts]
            dict set frames $id [dict create id $id kind $type label $label start [llength $messages] end {} depth [llength $stack] parent [lindex $stack end] branches {} line $number span $span annotated_span $annotatedSpan]
            lappend stack $id
            if {[llength $stack]>8 || [dict size $frames]>256} {_umlFail $number LIMIT {Sequence frames support depth 8 and 256 total frames}}
        } elseif {[regexp {^else(?:\s+(.+))?$} $line -> label]} {
            if {![llength $stack] || [dict get $frames [lindex $stack end] kind] ne {alt}} {_umlFail $number FRAME {else requires the current alt frame}}
            if {$label ne {}} {_umlLabel $label $number}
            set frameId [lindex $stack end];set frame [dict get $frames $frameId]
            dict lappend frame branches [dict create label $label order [llength $messages] span $span line $number]
            dict set frames $frameId $frame
            set id {};if {$pending ne {}} {_umlFail $number ID {else has no separate semantic identity}}
        } elseif {$line eq {end}} {
            if {![llength $stack]} {_umlFail $number FRAME {end has no opening sequence frame}}
            set frame [lindex $stack end];set stack [lrange $stack 0 end-1]
            dict set frames $frame end [llength $messages]
            dict set frames $frame close_span $span
            dict set frames $frame span [list [lindex [dict get $frames $frame span] 0] $end]
            set id {};if {$pending ne {}} {_umlFail $number ID {end has no separate semantic identity}}
        } else {_umlFail $number UNSUPPORTED {Unsupported or malformed GX-TXT PlantUML subset syntax; source remains intact}}
        if {$id ne {}} {
            if {[dict exists $seenIds $id]} {_umlFail $number ID {Semantic identity is duplicated}}
            dict set seenIds $id 1
        }
        set pending {};set pendingStart {}
    }
    if {!$opened || !$ended || $blockComment || $pending ne {}} {_umlFail [expr {max(1,$number)}] UNCLOSED {Expected a complete @startuml…@enduml diagram and attached identity annotations}}
    if {$family eq {}} {set family [expr {$expected eq {auto}?{class}:$expected}]}
    if {$expected ne {auto} && $expected ne $family} {_umlFail 1 FAMILY {Diagram family differs from its declared profile}}
    foreach item [concat $relations $messages] {
        foreach endpoint {from to} {if {![dict exists $elements [dict get $item $endpoint]]} {_umlFail [dict get $item line] REFERENCE {Declare every referenced class or participant explicitly}}}
        if {[dict get $item kind] in {generalization realization composition} && [dict get $item from] eq [dict get $item to]} {_umlFail [dict get $item line] RELATION {Generalization, realization and composition cannot point to self}}
        if {[dict get $item kind] eq {realization}} {
            set target [dict get $item [expr {[dict get $item marker] eq {start}?{from}:{to}}]]
            if {[dict get $elements $target type] ne {interface}} {_umlFail [dict get $item line] REALIZATION {A realization triangle must target an interface}}
        }
        if {[dict get $item kind] eq {composition}} {
            set whole [dict get $item [expr {[dict get $item marker] eq {start}?{left_multiplicity}:{right_multiplicity}}]]
            if {$whole ne {} && $whole ni {0 1 0..1 1..1}} {_umlFail [dict get $item line] COMPOSITION {The composite whole multiplicity must have an upper bound of one}}
        }
    }
    # Generalization cycles are invalid semantic models, independently of layout.
    set parents {}
    foreach item $relations {
        if {[dict get $item kind] ne {generalization}} continue
        set base [dict get $item [expr {[dict get $item marker] eq {start}?{from}:{to}}]]
        set child [dict get $item [expr {[dict get $item marker] eq {start}?{to}:{from}}]]
        if {[dict get $elements $base type] ne [dict get $elements $child type]} {_umlFail [dict get $item line] GENERALIZATION {Use realization between a class and an interface}}
        dict lappend parents $child $base
    }
    dict for {alias element} $elements {
        set todo [datasetPublicationV2DictDefault $parents $alias {}];set visited {}
        while {[llength $todo]} {
            set base [lindex $todo 0];set todo [lrange $todo 1 end]
            if {$base eq $alias} {_umlFail [dict get $element line] CYCLE {Generalization graph contains a cycle}}
            if {$base in $visited} continue
            lappend visited $base;lappend todo {*}[datasetPublicationV2DictDefault $parents $base {}]
        }
    }
    dict for {alias position} $positions {if {![dict exists $elements $alias]} {_umlFail [dict get $position line] POSITION {Position annotation refers to a missing element}}}
    foreach key {family title elements relations messages frames positions} {dict set result $key [set $key]}
}
proc ::GX::_umlReceipt {receipt} {
    if {[catch {dict size $receipt}] || ![dict exists $receipt source] || ![dict exists $receipt source_sha256] || [string bytelength $receipt]>16777216} {error {UML receipt must bind bounded authoritative source}}
    set actual [umlDocumentParse [dict get $receipt source]]
    if {[dict get $actual source_sha256] ne [dict get $receipt source_sha256]} {error {UML receipt source SHA changed}}
    if {![dict get $actual valid]} {error {UML source has diagnostics; the previous diagram cannot represent this source SHA}}
    # Never accept caller-forged derived nodes, spans, paths or render plans.
    return $actual
}
proc ::GX::umlDocumentInspectElement {receipt id} {
    set model [_umlReceipt $receipt]
    if {[dict exists $model elements $id]} {return [dict get $model elements $id]}
    foreach key {relations messages} {foreach item [dict get $model $key] {if {[dict get $item id] eq $id} {return $item}}}
    if {[dict exists $model frames $id]} {return [dict get $model frames $id]}
    dict for {alias element} [dict get $model elements] {foreach item [dict get $element members] {if {[dict get $item id] eq $id} {dict set item owner $alias;return $item}}}
    error {UML element no longer exists in this source}
}
proc ::GX::_umlRequest {request allowed required} {
    if {[catch {dict size $request}] || [string bytelength $request]>16384} {error {UML edit request must be a dictionary of at most 16 KiB}}
    foreach key [dict keys $request] {if {$key ni $allowed} {error "Unsupported UML edit field: $key"}}
    foreach key $required {if {![dict exists $request $key]} {error "UML edit requires $key"}}
}
proc ::GX::_umlNewId {source operation} {
    return gx_[string range [_umlDigest [list $source $operation [clock clicks]]] 0 23]
}
proc ::GX::_umlEol {source} {expr {[string first \r\n $source]>=0?"\r\n":"\n"}}
proc ::GX::_umlLineEol {source span} {
    set text [string range $source [lindex $span 0] [expr {[lindex $span 1]-1}]]
    if {[string match *\r\n $text]} {return "\r\n"}
    if {[string match *\n $text]} {return "\n"}
    return {}
}
proc ::GX::_umlSplice {source patches} {
    set limit [string length $source]
    foreach patch [lsort -integer -index 0 -decreasing $patches] {
        lassign $patch start end replacement
        if {![string is integer -strict $start] || ![string is integer -strict $end] || $start<0 || $end<$start || $end>$limit} {error {Overlapping or invalid UML source spans}}
        set source "[string range $source 0 [expr {$start-1}]]$replacement[string range $source $end end]"
        set limit $start
    }
    return $source
}
proc ::GX::_umlReplaceLine {source item text id} {
    set span [dict get $item span]
    if {[dict exists $item declaration_span]} {set span [dict get $item declaration_span]}
    set old [string range $source [lindex $span 0] [expr {[lindex $span 1]-1}]]
    set indent [lindex [regexp -inline {^[ \t]*} $old] 0]
    set eol [_umlLineEol $source $span]
    set replacement $indent$text$eol
    if {$id ne {} && [lindex [dict get $item annotated_span] 0]==[lindex $span 0]} {
        set replacement "$indent' @gx-id $id[_umlEol $source]$replacement"
    }
    return [list [lindex $span 0] [lindex $span 1] $replacement]
}
proc ::GX::_umlRelationLine {request} {
    _umlRequest $request {from to kind marker label left_multiplicity right_multiplicity id} {from to kind}
    set from [_umlAlias [dict get $request from] 1];set to [_umlAlias [dict get $request to] 1]
    set kind [dict get $request kind]
    set arrows {association -- dependency ..> generalization --|> realization ..|> composition *-- aggregation o--}
    if {![dict exists $arrows $kind]} {error {Choose an implemented UML relationship kind}}
    set marker [datasetPublicationV2DictDefault $request marker [expr {$kind in {composition aggregation}?{start}:{end}}]]
    if {$marker ni {start end}} {error {Relationship marker must be at the start or end endpoint}}
    if {$marker eq {start}} {set arrows {association -- dependency <.. generalization <|-- realization <|.. composition *-- aggregation o--}
    } else {set arrows {association -- dependency ..> generalization --|> realization ..|> composition --* aggregation --o}}
    set left [_umlMultiplicity [datasetPublicationV2DictDefault $request left_multiplicity {}] 1]
    set right [_umlMultiplicity [datasetPublicationV2DictDefault $request right_multiplicity {}] 1]
    set line $from
    if {$left ne {}} {append line " \"$left\""}
    append line " [dict get $arrows $kind]"
    if {$right ne {}} {append line " \"$right\""}
    append line " $to"
    set label [datasetPublicationV2DictDefault $request label {}]
    if {$label ne {}} {append line " : [_umlLabel $label 1]"}
    return $line
}
proc ::GX::_umlMessageLine {request} {
    _umlRequest $request {from to kind label before id} {from to kind label}
    set arrows {sync -> async ->> reply -->}
    set kind [dict get $request kind]
    if {![dict exists $arrows $kind]} {error {Choose sync, async or reply message kind}}
    return "[_umlAlias [dict get $request from] 1] [dict get $arrows $kind] [_umlAlias [dict get $request to] 1] : [_umlLabel [dict get $request label] 1]"
}
proc ::GX::_umlMessage {model id} {
    foreach item [dict get $model messages] {if {[dict get $item id] eq $id} {return $item}}
    error {Message no longer exists in the current source}
}
proc ::GX::umlDocumentEdit {source expectedSha operation request} {
    set model [umlDocumentParse $source]
    if {[dict get $model source_sha256] ne $expectedSha} {error {UML draft changed; semantic edit refused}}
    if {![dict get $model valid]} {error {Correct source diagnostics before semantic editing; draft retained}}
    set eol [_umlEol $source];set patches {};set affected {};set summary {}
    switch -- $operation {
        element_add {
            _umlRequest $request {type alias name} {type alias name}
            set type [dict get $request type];set alias [_umlAlias [dict get $request alias] 1]
            set allowed [expr {[dict get $model family] eq {class}?{class interface}:{participant actor}}]
            if {$type ni $allowed || [dict exists $model elements $alias]} {error {Choose a new alias and an element type in this diagram family}}
            set name [_umlLabel [dict get $request name] 1]
            set text "$type \"$name\" as $alias$eol"
            if {$type in {class interface}} {set text "$type \"$name\" as $alias \u007b$eol\u007d$eol"}
            set at [lindex [dict get $model end_span] 0]
            # Participant declarations precede the first message/frame.
            if {$type in {participant actor}} {
                foreach item [dict get $model messages] {set at [expr {min($at,[lindex [dict get $item annotated_span] 0])}]}
                dict for {id item} [dict get $model frames] {set at [expr {min($at,[lindex [dict get $item annotated_span] 0])}]}
            }
            lappend patches [list $at $at $text];set affected [list $alias];set summary {Insert one declared semantic element}
        }
        element_rename {
            _umlRequest $request {id name} {id name}
            set id [dict get $request id];set item [dict get $model elements $id]
            set name [_umlLabel [dict get $request name] 1]
            set text "[dict get $item type] \"$name\" as $id"
            if {[dict get $item close_span] ne {}} {append text " \u007b"}
            lappend patches [_umlReplaceLine $source $item $text {}]
            set affected [list $id];set summary {Change display name; stable alias and relationships preserved}
        }
        element_delete {
            _umlRequest $request {id cascade} {id cascade}
            if {![string is boolean -strict [dict get $request cascade]]} {error {Cascade confirmation must be boolean}}
            set id [dict get $request id];set item [dict get $model elements $id]
            foreach key {relations messages} {
                foreach relation [dict get $model $key] {
                    if {$id ni [list [dict get $relation from] [dict get $relation to]]} continue
                    if {![dict get $request cascade]} {error {Element has connected relationships/messages; explicit cascade confirmation is required}}
                    lappend patches [list {*}[dict get $relation annotated_span] {}]
                    lappend affected [dict get $relation id]
                }
            }
            lappend patches [list [lindex [dict get $item annotated_span] 0] [lindex [dict get $item span] 1] {}]
            if {[dict exists $model positions $id]} {lappend patches [list {*}[dict get $model positions $id span] {}]}
            lappend affected $id;set summary {Remove element and explicitly confirmed connected semantic items}
        }
        member_add {
            _umlRequest $request {owner text} {owner text}
            set alias [dict get $request owner];set item [dict get $model elements $alias]
            if {[dict get $item type] ni {class interface}} {error {Members belong to class/interface elements}}
            set text [dict get $request text]
            if {$text eq {} || [regexp {[\r\n]} $text]} {error {Enter one nonempty member line}}
            set id [_umlNewId $source $operation]
            set insert "  ' @gx-id $id$eol  $text$eol"
            if {[dict get $item close_span] ne {}} {
                set at [lindex [dict get $item close_span] 0];lappend patches [list $at $at $insert]
            } else {
                set line "[dict get $item type] \"[dict get $item name]\" as $alias \u007b$eol$insert\u007d"
                lappend patches [_umlReplaceLine $source $item $line {}]
            }
            set affected [list $id $alias];set summary {Insert a member with an explicit source identity annotation}
        }
        member_edit - relation_edit - message_edit {
            set id [dict get $request id];set item [umlDocumentInspectElement $model $id]
            switch -- $operation {
                member_edit {
                    _umlRequest $request {id text} {id text}
                    if {![dict exists $item visibility]} {error {Selected item is not a member}}
                    set text [dict get $request text]
                    if {$text eq {} || [regexp {[\r\n]} $text]} {error {Enter one nonempty member line}}
                }
                relation_edit {
                    if {![dict exists $item arrow]} {error {Selected item is not a class relationship}}
                    if {![dict exists $request marker]} {dict set request marker [dict get $item marker]}
                    set text [_umlRelationLine $request]
                }
                message_edit {if {![dict exists $item frames]} {error {Selected item is not a sequence message}};set text [_umlMessageLine $request]}
            }
            lappend patches [_umlReplaceLine $source $item $text $id]
            set affected [list $id];set summary {Replace one validated semantic line, retaining or explicitly anchoring its identity}
        }
        member_delete - relation_delete - message_delete {
            _umlRequest $request {id} {id}
            set id [dict get $request id];set item [umlDocumentInspectElement $model $id]
            set field [dict get {member_delete visibility relation_delete arrow message_delete frames} $operation]
            if {![dict exists $item $field]} {error {Selected item has a different semantic type}}
            lappend patches [list {*}[dict get $item annotated_span] {}]
            set affected [list $id];set summary {Remove one semantic item and its identity annotation}
        }
        relation_add - message_add {
            if {$operation eq {relation_add}} {
                if {[dict get $model family] ne {class}} {error {Relationships require a class diagram}}
                set text [_umlRelationLine $request]
            } else {
                if {[dict get $model family] ne {sequence}} {error {Messages require a sequence diagram}}
                set text [_umlMessageLine $request]
            }
            set at [lindex [dict get $model end_span] 0]
            set before [datasetPublicationV2DictDefault $request before {}]
            if {$before ne {}} {set at [lindex [dict get [_umlMessage $model $before] annotated_span] 0]}
            set id [_umlNewId $source $operation]
            lappend patches [list $at $at "' @gx-id $id$eol$text$eol"]
            set affected [list $id];set summary {Insert one relationship/message with an explicit stable source identity}
        }
        message_move {
            _umlRequest $request {id before after} {id}
            if {[dict exists $request before]==[dict exists $request after]} {error {Message move requires exactly one before or after semantic message target}}
            set id [dict get $request id];set item [_umlMessage $model $id]
            if {[dict exists $request after]} {
                set after [dict get $request after]
                if {$after eq $id} {error {Message already occupies that order}}
                set target [_umlMessage $model $after];set at [lindex [dict get $target span] 1];set context [dict get $target frame_context]
            } else {
                set before [dict get $request before]
                if {$before eq $id} {error {Message already occupies that order}}
                if {$before eq {}} {set at [lindex [dict get $model end_span] 0];set context {}} else {set target [_umlMessage $model $before];set at [lindex [dict get $target annotated_span] 0];set context [dict get $target frame_context]}
            }
            if {[dict get $item frame_context] ne $context} {error {Moving a message across control-frame or alt-branch boundaries requires an explicit frame edit}}
            lassign [dict get $item annotated_span] start end
            set text [string range $source $start [expr {$end-1}]]
            if {[lindex [dict get $item span] 0]==$start} {set text "' @gx-id $id$eol$text"}
            lappend patches [list $start $end {}] [list $at $at $text]
            set affected [list $id];set summary {Explicitly reorder one message within its existing control frame}
        }
        frame_add {
            _umlRequest $request {kind label first last} {kind label first last}
            set kind [dict get $request kind]
            if {$kind ni {alt opt loop}} {error {Choose alt, opt or loop}}
            set first [_umlMessage $model [dict get $request first]];set last [_umlMessage $model [dict get $request last]]
            if {[dict get $first order]>[dict get $last order] || [dict get $first frame_context] ne [dict get $last frame_context]} {error {Choose an ordered range in one existing control frame and branch}}
            set id [_umlNewId $source $operation];set label [_umlLabel [dict get $request label] 1]
            set begin [lindex [dict get $first annotated_span] 0];set end [lindex [dict get $last span] 1]
            lappend patches [list $begin $begin "' @gx-id $id$eol$kind $label$eol"] [list $end $end "end$eol"]
            set affected [list $id];set summary {Wrap an explicit ordered message range in a supported control frame}
        }
        frame_edit {
            _umlRequest $request {id label} {id label}
            set id [dict get $request id];set frame [dict get $model frames $id]
            set item $frame;dict set item span [list [lindex [dict get $frame span] 0] [expr {[string first \n $source [lindex [dict get $frame span] 0]]+1}]]
            set text "[dict get $frame kind] [_umlLabel [dict get $request label] 1]"
            lappend patches [_umlReplaceLine $source $item $text $id]
            set affected [list $id];set summary {Edit one control-frame condition without changing ordered messages}
        }
        frame_delete {
            _umlRequest $request {id} {id}
            set id [dict get $request id];set frame [dict get $model frames $id]
            set start [lindex [dict get $frame annotated_span] 0];set header [lindex [dict get $frame span] 0]
            set end [expr {[string first \n $source $header]+1}]
            lappend patches [list $start $end {}] [list {*}[dict get $frame close_span] {}]
            foreach branch [dict get $frame branches] {lappend patches [list {*}[dict get $branch span] {}]}
            set affected [list $id];set summary {Remove control frame and branch guards; preserve the explicit message order}
        }
        position_set {
            _umlRequest $request {id x y} {id x y}
            set id [dict get $request id];dict get $model elements $id
            set x [dict get $request x];set y [dict get $request y]
            foreach value [list $x $y] {if {![string is double -strict $value] || ![expr {abs($value)<=50000}]} {error {Layout coordinates must be finite within 50000 units}}}
            if {[dict get $model family] eq {sequence} && $y!=0} {error {Sequence participant movement is horizontal; message order uses explicit reordering}}
            set text "' @gx-position $id $x $y$eol"
            if {[dict exists $model positions $id]} {lappend patches [list {*}[dict get $model positions $id span] $text]} else {set at [lindex [dict get $model end_span] 0];lappend patches [list $at $at $text]}
            set affected [list $id];set summary {Record presentation position in an explicit source comment; semantic links/order unchanged}
        }
        layout_reset {
            _umlRequest $request {} {}
            dict for {id position} [dict get $model positions] {lappend patches [list {*}[dict get $position span] {}]}
            set summary {Remove only GX-TXT position annotations and restore automatic layout}
        }
        default {error {Unknown finite UML semantic edit operation}}
    }
    set candidate [_umlSplice $source $patches]
    set parsed [umlDocumentParse $candidate [dict create family [dict get $model family]]]
    if {![dict get $parsed valid]} {
        set diagnostic [lindex [dict get $parsed diagnostics] 0]
        return -code error -errorcode [list GX UML [dict get $diagnostic line] [dict get $diagnostic code]] "Edit refused: [dict get $diagnostic message]"
    }
    return [dict create schema gxtxt.uml.edit.v1 status edited operation $operation summary $summary affected_ids $affected changed_spans $patches \
        expected_source_sha256 $expectedSha source $candidate source_sha256 [dict get $parsed source_sha256] parsed $parsed]
}
source [file join [file dirname [info script]] uml_layout_v1.tcl]
proc ::GX::_umlMetadataField {dictionary key {default {}}} {
    if {[dict exists $dictionary $key]} {return [dict get $dictionary $key]}
    return $default
}
proc ::GX::umlDocumentDescribe {id {options {}}} {
    set session [_interactiveDocumentRequireSession]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::umlDocumentDescribe $id $options]}
    set description [datasetDocumentDescribe $id $options]
    if {[dict get $description contract] ne {document.uml}} {error {Choose a canonical UML Dataset}}
    set metadata [dict get $description metadata]
    foreach key {profile family parser_version source_sha256} {
        dict set description declared_$key [_umlMetadataField $metadata uml.$key]
    }
    # These remain literal Registry declarations, not inferred source provenance.
    foreach key {source_module producer_module producer_version provenance source source_dataset_ids} {
        dict set description $key [datasetField $id $key {}]
    }
    dict set description namespace [datasetNamespaceGet $session $id]
    set producer [dict get $description producer_module]
    dict set description installed_producer_version [moduleField $producer version {}]
    dict set description installed_producer_dependencies [moduleField $producer depends {}]
    return $description
}
proc ::GX::umlDocumentRead {id {options {}}} {
    set description [umlDocumentDescribe $id $options]
    set read [datasetDocumentRead $id 4194304]
    if {![dict get $read complete]} {error {UML source exceeds the complete 4 MiB document bound}}
    _documentSessionCheck [dict get $description session]
    if {[datasetRevisionToken $id] ne [dict get $description revision]} {error {Canonical UML changed while reading; reopen its current revision}}
    set parsed [umlDocumentParse [dict get $read source]]
    if {[dict get $parsed source_sha256] ne [dict get $description sha256]} {error {UML decoded source differs from the authoritative payload SHA}}
    set declared [dict get $description declared_profile]
    if {$declared ne {} && $declared ne {gxtxt.plantuml.v1}} {
        dict set parsed valid 0
        dict set parsed diagnostics [list [_umlDiagnostic 1 PROFILE {Declared UML profile is unsupported; original source remains inspectable}]]
    }
    return [dict merge $read [dict create description $description parsed $parsed]]
}
proc ::GX::umlDocumentWrite {capability request} {
    set session [_documentWriteRequestCheck $capability $request]
    return [datasetAuthorityTransaction $session ::GX::_datasetDocumentWrite $capability $request uml]
}
source [file join [file dirname [info script]] uml_diagram_host_v1.tcl]
source [file join [file dirname [info script]] uml_editor_v1.tcl]
