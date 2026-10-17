# GX-TXT Mathematics Explorer — Tcl/Tk UI; no scientific algorithms or private renderers.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::MathematicsExplorer {variable ui}

proc ::GX::MathematicsExplorer::_status {w message} {
    variable ui
    if {[winfo exists $w]} {set ui($w,status) $message}
}
proc ::GX::MathematicsExplorer::_notify {w message} {
    _status $w $message
    if {[winfo exists $w]} {
        tk_messageBox -parent $w -title {Mathematics Explorer} -icon error -type ok -message $message
    }
}
proc ::GX::MathematicsExplorer::_uiReadState {w} {
    variable ui
    set funcs {}
    for {set i 1} {$i <= 3} {incr i} {
        lappend funcs [dict create id f$i label $ui($w,label$i) preset $ui($w,preset$i) \
            enabled $ui($w,enabled$i) expression $ui($w,expr$i)]
    }
    set s [dict create schema 1 title $ui($w,title) xmin $ui($w,xmin) \
        xmax $ui($w,xmax) samples $ui($w,samples) \
        parameters [dict create a $ui($w,a) b $ui($w,b) c $ui($w,c)] \
        derivative $ui($w,derivative) functions $funcs \
        symbol_units [dict create x $ui($w,unit_x) a $ui($w,unit_a) b $ui($w,unit_b) c $ui($w,unit_c)] \
        output_unit $ui($w,unit_y) view_axes {}]
    if {[info exists ui($w,view_units)] && $ui($w,view_units) eq [list [dict get $s symbol_units] [dict get $s output_unit]]} {
        dict set s view_axes $ui($w,view_axes)
        if {[winfo exists $w.right.plot.native]} {
            set receipt [::GX::PlotDatasetAPIv4::widgetReceipt $w.right.plot.native]
            if {[dict exists $receipt axes]} {dict set s view_axes [dict get $receipt axes]}
        }
    }
    return [validateState $s]
}
proc ::GX::MathematicsExplorer::_uiSetState {w s} {
    variable ui
    set s [validateState $s]
    foreach key {x a b c} {set ui($w,unit_$key) [dict get $s symbol_units $key]}
    set ui($w,unit_y) [dict get $s output_unit]
    set ui($w,view_axes) [dict get $s view_axes];set ui($w,view_units) [list [dict get $s symbol_units] [dict get $s output_unit]]
    if {[winfo exists $w.right.plot.native]} {::GX::PlotDatasetAPIv4::widgetDestroy $w.right.plot.native;destroy $w.right.plot.native}
    set ui($w,updating) 1
    foreach k {title xmin xmax samples derivative} {set ui($w,$k) [dict get $s $k]}
    foreach k {a b c} {
        set ui($w,$k) [dict get $s parameters $k]
        set n [dict get $s parameters $k]
        if {$n >= -10 && $n <= 10} {$w.left.parameters.control.$k.scale set $n}
    }
    set i 0
    foreach fn [dict get $s functions] {
        incr i
        foreach {field key} {label label preset preset enabled enabled expr expression} {
            set ui($w,$field$i) [dict get $fn $key]
        }
    }
    set ui($w,updating) 0
    if {[info exists ui($w,photo)] && $ui($w,photo) ne ""} {
        catch {$w.right.plot.canvas itemconfigure figure -image ""}
        catch {image delete $ui($w,photo)}
        set ui($w,photo) ""
    }
    set ui($w,computed) ""
    set ui($w,computed_state) ""
    set ui($w,integral) {Integration not calculated}
    set ui($w,changed) 0
    _status $w {Model loaded. Plot to evaluate and inspect it.}
}
proc ::GX::MathematicsExplorer::_uiChanged {w} {
    variable ui
    if {![winfo exists $w]} return
    set ui($w,changed) 1
    _uiSchedule $w
}
proc ::GX::MathematicsExplorer::_uiSchedule {w} {
    variable ui
    if {[info exists ui($w,pending)] && $ui($w,pending) ne ""} {
        after cancel $ui($w,pending)
    }
    # Debounce avoids repeating Octave work for each keystroke.
    set ui($w,pending) [after 900 [list ::GX::MathematicsExplorer::_uiPlot $w]]
}
proc ::GX::MathematicsExplorer::_uiSlider {w parameter value} {
    variable ui
    if {![winfo exists $w] || ([info exists ui($w,updating)] && $ui($w,updating))} return
    set ui($w,$parameter) [format %.4g $value]
    _uiChanged $w
}
proc ::GX::MathematicsExplorer::_uiPreset {w i} {
    variable ui
    set preset $ui($w,preset$i)
    if {$preset ne "Custom"} {set ui($w,expr$i) [dict get [presets] $preset]}
    _uiChanged $w
}
proc ::GX::MathematicsExplorer::_uiExpressionEdited {w i} {
    variable ui
    if {![winfo exists $w]} return
    set preset $ui($w,preset$i)
    if {$preset ne "Custom" && $ui($w,expr$i) ne [dict get [presets] $preset]} {
        set ui($w,preset$i) Custom
    }
    _uiChanged $w
}
proc ::GX::MathematicsExplorer::_uiPlot {w} {
    variable ui
    if {![winfo exists $w]} return
    set ui($w,pending) ""
    if {[catch {
        set state [_uiReadState $w]
        if {$ui($w,session_token) ne [sessionToken]} {error "The Session has changed: close and reopen the viewer."}
        _status $w {Evaluating with NUMERIC_API_v1; preparing native interactive graph...}
        update idletasks
        set result [calculate $state]
        ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
        set native [nativeModel $state $result]
        if {[winfo exists $w.right.plot.native]} {
            ::GX::PlotDatasetAPIv4::widgetConfigure $w.right.plot.native $native {prepared_model 1}
        } else {
            ::GX::PlotDatasetAPIv4::widgetCreate $w.right.plot.native $native {prepared_model 1}
            pack $w.right.plot.native -fill both -expand 1
            bind $w.right.plot.native <Button-1> [list [namespace current]::_uiPick $w %x %y]
        }
        if {[dict get $state view_axes] ne {}} {::GX::PlotDatasetAPIv4::widgetView $w.right.plot.native restore [dict get $state view_axes]} else {::GX::PlotDatasetAPIv4::widgetView $w.right.plot.native fit}
        set ui($w,view_units) [list [dict get $state symbol_units] [dict get $state output_unit]]
        set ui($w,computed) $result
        set ui($w,computed_state) $state
        _status $w "[llength [dict get $result series]] trace(s), [dict get $state samples] samples; explicit physical units; public Numeric and native graph."
    } message options]} {
        set ui($w,computed) ""
        set ui($w,computed_state) ""
        catch {$w.right.plot.canvas itemconfigure figure -image ""}
        if {$ui($w,photo) ne ""} {catch {image delete $ui($w,photo)}; set ui($w,photo) ""}
        _status $w "Not evaluated: $message. Previous valid graph, if present, is retained."
    }
}
proc ::GX::MathematicsExplorer::_uiPick {w x y} {
    variable ui
    if {[catch {
        if {$ui($w,session_token) ne [sessionToken]} {error {Point belongs to another Session}}
        set hit [::GX::PlotDatasetAPIv4::widgetHit $w.right.plot.native $x $y]
        if {[dict get $hit hit]&&[dict exists $hit source_row_ordinal]} {
            dict set hit document_id $ui($w,doc_id);set ui($w,last_pick) $hit
            _status $w "[dict get $hit series_id] sample [dict get $hit source_row_ordinal]: x=[dict get $hit x], y=[dict get $hit y]; declared graph units"
        }
    } message]} {_status $w $message}
}
proc ::GX::MathematicsExplorer::_uiEnsureCurrent {w} {
    variable ui
    set state [_uiReadState $w]
    if {$ui($w,computed) eq "" || [dict remove $ui($w,computed_state) view_axes] ne [dict remove $state view_axes]} {
        _uiPlot $w
    }
    if {$ui($w,computed) eq "" || [dict remove $ui($w,computed_state) view_axes] ne [dict remove $state view_axes]} {
        error "Evaluate the current model successfully before this operation."
    }
    return [list $state $ui($w,computed)]
}
proc ::GX::MathematicsExplorer::_uiPublishOnly {w} {variable ui;set ui($w,publish_graph) 0;_uiPublishDialog $w}
proc ::GX::MathematicsExplorer::_uiPublishGraph {w} {variable ui;set ui($w,publish_graph) 1;_uiPublishDialog $w}
proc ::GX::MathematicsExplorer::_uiAnalyze {w} {
    variable ui
    if {[catch {
        set state [_uiReadState $w];set mode $ui($w,analysis_mode)
        if {$mode ni {roots intersections extrema}} {error {Invalid mathematical analysis}}
        if {$ui($w,session_token) ne [sessionToken]} {error {Session changed; reopen this Viewer}}
        if {$ui($w,doc_id) eq {} || [dict remove $state view_axes] ne [dict remove $ui($w,saved_state) view_axes]} {error {Save the current model before managed analysis}}
        if {[info exists ui($w,analysis_job)] && [dict get [::GX::scriptJobDescribe [dict get $ui($w,analysis_job) job_id]] state] ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {error {An analysis is already managed in Jobs; cancel it or wait}}
        set document [::GX::interactiveDocumentRead $ui($w,doc_id)]
        set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $state]]
        # Only inert bounded state is interpolated as Base64. The actual public
        # Numeric Bridge and existing durable Script Job own execution/cancel.
        set code [string map [list @STATE@ $encoded @MODE@ $mode] {
from gxtxt import gxtxt_api_call as call
import base64,json,tkinter,numpy as np
tcl=tkinter.Tcl()
def data_dict(value):
    pairs=tcl.splitlist(value)
    if len(pairs)%2: raise ValueError('Invalid inert state dictionary')
    return dict(zip(pairs[::2],pairs[1::2]))
s=data_dict(base64.b64decode('@STATE@').decode('utf-8'))
f=[data_dict(value) for value in tcl.splitlist(s['functions'])]
if f[0]['enabled']!='1': raise ValueError('Enable Function1 for analysis')
request={'expression':f[0]['expression'],'variable':'x','interval':[float(s['xmin']),float(s['xmax'])],
         'symbols':{k:float(v) for k,v in data_dict(s['parameters']).items()},'symbol_units':data_dict(s['symbol_units']),'mode':'@MODE@'}
if request['mode']=='intersections':
    if f[1]['enabled']!='1': raise ValueError('Enable Function2 for intersections')
    request['expression2']=f[1]['expression']
r=call('NUMERIC_API_v1','expression_analyze',[request,{'output_unit':s['output_unit']}])
def plain(value):
    if hasattr(value,'values'): return np.asarray(value.values).reshape(value.shape).tolist()
    return np.asarray(value).tolist()
text=json.dumps(r,indent=2,default=plain,ensure_ascii=False)
print('GXTXT_MATH_RESULT:'+base64.b64encode(text.encode('utf-8')).decode('ascii'),flush=True)
}]
        set id mathematical_analysis_[clock clicks]
        ::GX::scriptRegistrySave session $id {Mathematical expression analysis} $code [dict create language Python required_apis NUMERIC_API_v1]
        set job [::GX::scriptJobSubmit session:$id {}]
        set ui($w,analysis_job) [dict create job_id [dict get $job id] session_token [sessionToken] \
            document_id $ui($w,doc_id) generation [dict get $document generation] revision [dict get $document revision] source_state [dict remove $state view_axes]]
        $w.top.cancel configure -state normal
        _status $w "Managed mathematical analysis: [dict get $job id]"
        set ui($w,analysis_pending) [after 150 [list [namespace current]::_uiPollAnalysis $w]]
    } message]} {_notify $w $message}
}
proc ::GX::MathematicsExplorer::_uiCancelAnalysis {w} {
    variable ui
    if {![info exists ui($w,analysis_job)]} return
    if {[catch {::GX::scriptJobCancel [dict get $ui($w,analysis_job) job_id]} message]} {_notify $w $message}
}
proc ::GX::MathematicsExplorer::_uiPollAnalysis {w} {
    variable ui
    if {![winfo exists $w]||![info exists ui($w,analysis_job)]} return
    set ui($w,analysis_pending) {}
    set code [catch {
        set ticket $ui($w,analysis_job);set state [::GX::scriptJobDescribe [dict get $ticket job_id]];set phase [dict get $state state]
        if {$phase ni {COMPLETED FAILED CANCELLED INTERRUPTED}} {
            _status $w "Mathematical analysis: $phase"
            set ui($w,analysis_pending) [after 150 [list [namespace current]::_uiPollAnalysis $w]];return
        }
        $w.top.cancel configure -state disabled
        if {$phase ne {COMPLETED}} {_status $w "Mathematical analysis $phase; its actual log remains in Jobs";set ui($w,last_analysis) [dict create state $phase job_id [dict get $ticket job_id]];return}
        if {[sessionToken] ne [dict get $ticket session_token]||$ui($w,doc_id) ne [dict get $ticket document_id]||[dict remove [_uiReadState $w] view_axes] ne [dict get $ticket source_state]} {error {Model or Session changed; completed result remains in Jobs and is not adopted}}
        set document [::GX::interactiveDocumentRead $ui($w,doc_id)]
        if {[dict get $document generation] ne [dict get $ticket generation]||[dict get $document revision] ne [dict get $ticket revision]} {error {Saved model revision changed; completed result remains in Jobs}}
        set log {};set offset 0
        while {1} {
            set chunk [::GX::scriptJobLogRead [dict get $ticket job_id] $offset 65536]
            if {![dict get $chunk available]} {error [dict get $chunk diagnostic]}
            append log [dict get $chunk content];if {[string bytelength $log]>524288} {error {Mathematical result log exceeds bounded inspection size}}
            if {[dict get $chunk eof]} break
            set offset [dict get $chunk next_offset]
        }
        if {![regexp -line {^GXTXT_MATH_RESULT:([A-Za-z0-9+/=]+)$} $log unused encoded]} {error {Completed mathematical Job has no valid result receipt; inspect Jobs}}
        set text [encoding convertfrom utf-8 [binary decode base64 -strict $encoded]]
        set ui($w,last_analysis) [dict create state COMPLETED text $text job_id [dict get $ticket job_id]]
        set d $w.analysis;catch {destroy $d};toplevel $d;wm title $d {Mathematical analysis}
        text $d.value -width 75 -height 20 -wrap word;$d.value insert end $text;$d.value configure -state disabled;pack $d.value -fill both -expand 1
        ttk::button $d.close -text Close -command [list destroy $d];pack $d.close -side bottom
        _status $w {Analysis completed; finite sampling does not prove all solutions}
    } message options]
    if {$code==2} {return -options $options $message}
    if {$code} {
        catch {$w.top.cancel configure -state disabled}
        _status $w $message
    }
}
proc ::GX::MathematicsExplorer::_uiIntegral {w} {
    variable ui
    if {[catch {
        lassign [_uiEnsureCurrent $w] state computed
        set i [integralOfFirst $computed]
        set plan [::GX::unitRegistryArithmeticPlan * [dict get $state symbol_units x] [dict get $state output_unit]]
        set i [expr {$i*[dict get $plan left_scale]*[dict get $plan right_scale]}]
        set ui($w,integral) [format {Integral F1 on [%.7g, %.7g] = %.10g %s (sampled trapezoidal result)} \
            [dict get $state xmin] [dict get $state xmax] $i [dict get $plan output_unit]]
        _status $w $ui($w,integral)
    } message]} {_notify $w $message}
}
proc ::GX::MathematicsExplorer::_uiSave {w} {
    variable ui
    if {[catch {
        set state [_uiReadState $w]
        set ui($w,doc_id) [saveDocument $state $ui($w,doc_id) $ui($w,session_token)]
        set ui($w,saved_state) $state
        _status $w "Saved Session document: $ui($w,doc_id)"
    } message]} {_notify $w $message; return 0}
    return 1
}
proc ::GX::MathematicsExplorer::_uiNew {w} {
    variable ui
    if {![_uiConfirmDiscard $w]} return
    set ui($w,doc_id) ""
    _uiSetState $w [initialState]
    set ui($w,saved_state) [_uiReadState $w]
    _uiSchedule $w
}
proc ::GX::MathematicsExplorer::_uiConfirmDiscard {w} {
    variable ui
    if {[catch {set now [_uiReadState $w]}]} {set now changed}
    if {$now eq $ui($w,saved_state)} {return 1}
    set decision [tk_messageBox -parent $w -title {Unsaved mathematics work} \
        -message {The current mathematical model has unsaved changes. Save before continuing?} \
        -icon question -type yesnocancel]
    if {$decision eq "cancel"} {return 0}
    if {$decision eq "yes"} {return [_uiSave $w]}
    return 1
}
proc ::GX::MathematicsExplorer::_uiOpenDialog {w} {
    variable ui
    if {[catch {set docs [listDocuments]} message]} {_notify $w $message; return}
    set d $w.documents
    catch {destroy $d}
    toplevel $d
    wm title $d {Session Mathematics Documents}
    wm geometry $d 510x340
    ttk::label $d.info -text {Select a saved Mathematics Explorer document in this Session.} -padding 8
    pack $d.info -fill x
    listbox $d.list -exportselection 0 -height 12
    pack $d.list -fill both -expand 1 -padx 8
    set ui($w,document_ids) {}
    foreach doc $docs {
        set id [dict get $doc id]
        lappend ui($w,document_ids) $id
        $d.list insert end "$id     [dict get $doc updated_at]"
    }
    ttk::button $d.open -text Open -command [list ::GX::MathematicsExplorer::_uiOpenSelection $w $d]
    ttk::button $d.cancel -text Cancel -command [list destroy $d]
    pack $d.cancel $d.open -side right -padx 8 -pady 8
    bind $d.list <Double-1> [list ::GX::MathematicsExplorer::_uiOpenSelection $w $d]
}
proc ::GX::MathematicsExplorer::_uiOpenSelection {w d} {
    variable ui
    if {![winfo exists $d]} return
    set index [lindex [$d.list curselection] 0]
    if {$index eq ""} return
    if {![_uiConfirmDiscard $w]} return
    set id [lindex $ui($w,document_ids) $index]
    if {[catch {set state [readDocument $id $ui($w,session_token)]} message]} {
        _notify $w $message; return
    }
    _uiSetState $w $state
    set ui($w,doc_id) $id
    set ui($w,saved_state) $state
    destroy $d
    _uiSchedule $w
}
proc ::GX::MathematicsExplorer::_uiPublishDialog {w} {
    variable ui
    if {[catch {_uiEnsureCurrent $w} message]} {_notify $w $message; return}
    set d $w.publish
    catch {destroy $d}
    toplevel $d
    wm title $d {Publish mathematical Dataset}
    set ui($w,output_id) mathematics.explorer.result
    if {![info exists ui($w,publish_graph)]} {set ui($w,publish_graph) 0}
    ttk::label $d.info -padding 8 -text {New Dataset ID (existing scientific data will not be overwritten):}
    ttk::entry $d.entry -textvariable ::GX::MathematicsExplorer::ui($w,output_id) -width 40
    ttk::label $d.hint -padding 8 -text {Variables: x, enabled f1/f2/f3, optional f1_derivative. Explicit checked physical units.}
    ttk::button $d.ok -text Publish -command [list ::GX::MathematicsExplorer::_uiPublishNow $w $d]
    ttk::button $d.cancel -text Cancel -command [list destroy $d]
    pack $d.info $d.entry $d.hint -fill x -padx 8
    pack $d.cancel $d.ok -side right -padx 8 -pady 8
    focus $d.entry
}
proc ::GX::MathematicsExplorer::_uiPublishNow {w d} {
    variable ui
    if {[catch {
        lassign [_uiEnsureCurrent $w] state computed
        if {$ui($w,doc_id) eq "" || $ui($w,saved_state) ne $state} {
            error "Save the current mathematical model before publishing."
        }
        if {$ui($w,publish_graph)} {
            set published [publishGraph $state $computed $ui($w,doc_id) $ui($w,session_token) $ui($w,output_id)]
        } else {set published [publishComputed $state $computed $ui($w,doc_id) $ui($w,session_token) $ui($w,output_id)]}
        set ui($w,last_publication) $published
        destroy $d
        _status $w "Published canonical Dataset: $ui($w,output_id)"
    } message]} {_notify $w $message}
}
proc ::GX::MathematicsExplorer::_uiClose {w} {
    variable ui
    if {![winfo exists $w]} return
    if {![_uiConfirmDiscard $w]} return
    if {[info exists ui($w,pending)] && $ui($w,pending) ne ""} {catch {after cancel $ui($w,pending)}}
    if {[info exists ui($w,photo)] && $ui($w,photo) ne ""} {catch {image delete $ui($w,photo)}}
    catch {::GX::PlotDatasetAPIv4::widgetDestroy $w.right.plot.native}
    destroy $w
    foreach key [array names ui "$w,*"] {unset ui($key)}
}
proc ::GX::MathematicsExplorer::_uiDestroyed {w actual} {
    variable ui
    if {$actual ne $w} return
    if {[info exists ui($w,pending)]&&$ui($w,pending) ne {}} {after cancel $ui($w,pending)}
    if {[info exists ui($w,analysis_pending)]&&$ui($w,analysis_pending) ne {}} {after cancel $ui($w,analysis_pending)}
    catch {::GX::PlotDatasetAPIv4::widgetDestroy $w.right.plot.native}
    array unset ui $w,*
}
proc ::GX::MathematicsExplorer::open {{context {}}} {
    variable ui
    package require Tk
    set token [sessionToken]
    set w .gx_mathematics_explorer
    if {[winfo exists $w]} {
        if {$ui($w,session_token) ne $token} {error "Existing Mathematics Explorer is bound to another Session. Close it first."}
        raise $w; focus $w; return $w
    }
    toplevel $w
    wm title $w {GX-TXT | Mathematics Explorer}
    wm geometry $w 1240x780
    wm minsize $w 1000 620
    set ui($w,session_token) $token
    set ui($w,doc_id) ""; set ui($w,photo) ""; set ui($w,pending) ""
    set ui($w,saved_state) [initialState]
    set ui($w,status) {Choose a function and parameters, then Plot.}
    set ui($w,integral) {Integral not calculated}

    ttk::frame $w.top -padding 8; pack $w.top -fill x
    ttk::label $w.top.heading -text {Mathematics Explorer}
    pack $w.top.heading -side left -padx {0 20}
    foreach {key label handler} {new New _uiNew open Open... _uiOpenDialog save {Save model} _uiSave plot {Plot / Refresh} _uiPlot integral {Integrate F1} _uiIntegral publish {Publish Dataset...} _uiPublishOnly graph {Publish Graph...} _uiPublishGraph analyze Analyze _uiAnalyze cancel {Cancel analysis} _uiCancelAnalysis} {
        ttk::button $w.top.$key -text $label -command [list ::GX::MathematicsExplorer::$handler $w]
        pack $w.top.$key -side left -padx 3
    }
    $w.top.cancel configure -state disabled
    ttk::panedwindow $w.pane -orient horizontal
    pack $w.pane -fill both -expand 1 -padx 8 -pady 4
    ttk::frame $w.left -padding 4
    ttk::frame $w.right -padding 4
    $w.pane add $w.left -weight 2
    $w.pane add $w.right -weight 3

    ttk::labelframe $w.left.functions -text {Functions — select, then edit expression} -padding 8
    pack $w.left.functions -fill x -pady {0 6}
    for {set i 1} {$i <= 3} {incr i} {
        ttk::frame $w.left.functions.f$i
        pack $w.left.functions.f$i -fill x -pady 5
        set row $w.left.functions.f$i
        ttk::checkbutton $row.on -text F$i -variable ::GX::MathematicsExplorer::ui($w,enabled$i) \
            -command [list ::GX::MathematicsExplorer::_uiChanged $w]
        ttk::entry $row.label -width 18 -textvariable ::GX::MathematicsExplorer::ui($w,label$i)
        ttk::combobox $row.preset -state readonly -width 12 -values [dict keys [presets]] \
            -textvariable ::GX::MathematicsExplorer::ui($w,preset$i)
        ttk::entry $row.expr -textvariable ::GX::MathematicsExplorer::ui($w,expr$i)
        pack $row.on -side left
        pack $row.label -side left -padx 3
        pack $row.preset -side left -padx 3
        pack $row.expr -fill x -expand 1 -padx 3
        bind $row.preset <<ComboboxSelected>> [list ::GX::MathematicsExplorer::_uiPreset $w $i]
        bind $row.expr <KeyRelease> [list ::GX::MathematicsExplorer::_uiExpressionEdited $w $i]
        bind $row.label <KeyRelease> [list ::GX::MathematicsExplorer::_uiChanged $w]
    }
    ttk::label $w.left.syntax -text {Supported: x, a/b/c, pi; + - * / ^; sin cos tan exp log log10 sqrt abs. Real results only.} -wraplength 480
    pack $w.left.syntax -fill x -pady {0 8}

    ttk::labelframe $w.left.parameters -text {Parameters — numeric field or slider [-10, 10]} -padding 8
    pack $w.left.parameters -fill x -pady {0 6}
    ttk::frame $w.left.parameters.control
    pack $w.left.parameters.control -fill x
    foreach p {a b c} {
        ttk::frame $w.left.parameters.control.$p
        set row $w.left.parameters.control.$p
        pack $row -fill x -pady 3
        ttk::label $row.name -text $p -width 3
        ttk::entry $row.entry -width 10 -textvariable ::GX::MathematicsExplorer::ui($w,$p)
        ttk::scale $row.scale -from -10 -to 10 -orient horizontal \
            -command [list ::GX::MathematicsExplorer::_uiSlider $w $p]
        pack $row.name $row.entry -side left -padx 2
        pack $row.scale -side left -fill x -expand 1 -padx 6
        bind $row.entry <Return> [list ::GX::MathematicsExplorer::_uiChanged $w]
        bind $row.entry <FocusOut> [list ::GX::MathematicsExplorer::_uiChanged $w]
    }
    ttk::labelframe $w.left.domain -text {Domain and numerical sampling} -padding 8
    pack $w.left.domain -fill x -pady {0 6}
    ttk::labelframe $w.left.units -text {Explicit units (1 = dimensionless)} -padding 6
    pack $w.left.units -fill x -pady 4
    foreach key {x a b c y} {
        ttk::frame $w.left.units.$key
        ttk::label $w.left.units.$key.label -text $key
        ttk::entry $w.left.units.$key.entry -width 8 -textvariable ::GX::MathematicsExplorer::ui($w,unit_$key)
        pack $w.left.units.$key -side left -padx 3
        pack $w.left.units.$key.label $w.left.units.$key.entry -side left
        bind $w.left.units.$key.entry <Return> [list ::GX::MathematicsExplorer::_uiChanged $w]
    }
    set ui($w,analysis_mode) roots
    ttk::combobox $w.left.mode -state readonly -values {roots intersections extrema} -textvariable ::GX::MathematicsExplorer::ui($w,analysis_mode)
    pack $w.left.mode -fill x -pady 3
    foreach {field caption} {xmin {X min} xmax {X max} samples Samples} {
        ttk::frame $w.left.domain.$field
        set row $w.left.domain.$field
        pack $row -side left -padx 8
        ttk::label $row.label -text $caption
        ttk::entry $row.value -textvariable ::GX::MathematicsExplorer::ui($w,$field) -width 10
        pack $row.label $row.value -side left -padx 2
        bind $row.value <Return> [list ::GX::MathematicsExplorer::_uiChanged $w]
        bind $row.value <FocusOut> [list ::GX::MathematicsExplorer::_uiChanged $w]
    }
    ttk::checkbutton $w.left.derivative -text {Show sampled derivative of F1} \
        -variable ::GX::MathematicsExplorer::ui($w,derivative) \
        -command [list ::GX::MathematicsExplorer::_uiChanged $w]
    pack $w.left.derivative -anchor w -pady 8
    ttk::label $w.left.scope -text {Real functions with explicit units; Analyze uses F1 (and F2 for intersections). Roots/extrema use bounded sampling and public solvers; completeness and uncertainty are not guaranteed.} -wraplength 490
    pack $w.left.scope -fill x -pady 7
    ttk::label $w.left.integral -textvariable ::GX::MathematicsExplorer::ui($w,integral) -wraplength 500
    pack $w.left.integral -fill x -pady 7

    ttk::frame $w.right.title
    pack $w.right.title -fill x -pady {0 5}
    ttk::label $w.right.title.label -text {Plot title:}
    ttk::entry $w.right.title.entry -textvariable ::GX::MathematicsExplorer::ui($w,title)
    pack $w.right.title.label -side left
    pack $w.right.title.entry -fill x -expand 1 -side left -padx 4
    bind $w.right.title.entry <KeyRelease> [list ::GX::MathematicsExplorer::_uiChanged $w]
    ttk::labelframe $w.right.plot -text {Interactive native mathematical graph} -padding 6
    pack $w.right.plot -fill both -expand 1
    ttk::label $w.right.caption -text {Wheel zooms, middle drag pans, double-click fits. Save model retains the exact viewport. Publication freezes a separate canonical Dataset and Graph.} -wraplength 680
    pack $w.right.caption -fill x -pady 6
    ttk::label $w.status -textvariable ::GX::MathematicsExplorer::ui($w,status) -anchor w -padding 8
    pack $w.status -fill x
    wm protocol $w WM_DELETE_WINDOW [list ::GX::MathematicsExplorer::_uiClose $w]
    bind $w <Destroy> [list ::GX::MathematicsExplorer::_uiDestroyed $w %W]
    ::GX::documentationBrowserAttachViewerHelp viewer.mathematics_explorer mathematics_explorer $w

    _uiSetState $w [initialState]
    set ui($w,saved_state) [_uiReadState $w]
    if {[dict exists $context document_id]} {
        set id [dict get $context document_id]
        if {[catch {set restored [readDocument $id $token]} reason]} {
            destroy $w
            error "Failed to restore the requested Mathematics Document: $reason"
        }
        _uiSetState $w $restored
        set ui($w,doc_id) $id
        set ui($w,saved_state) $restored
    }
    _uiSchedule $w
    return $w
}
proc ::GX::MathematicsExplorer::viewerDispatch {action scene} {
    if {$action ni {open rerender}} {error "Unsupported viewer dispatch '$action'."}
    set context [expr {[dict exists $scene open_context] ? [dict get $scene open_context] : [dict create]}]
    return [open $context]
}
