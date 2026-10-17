lassign $argv root out
if {[file exists $out] || ![string match */_private_dev106/* [file normalize $out]]} {error {Fresh private output required}}
file mkdir $out
load [file join $root core nativegui document libgxtxt_document[info sharedlibextension]] Gxtxtdocument
proc check {test label} {if {![uplevel 1 [list expr $test]]} {error "FAIL $label"};dict set ::checks $label PASS}
set checks {};set emoji [encoding convertfrom utf-8 [binary decode hex f09f9880]]
set source "x = '$emoji'; y = 2\n"
set model [::GX::NativeDocument::scan python $source]
foreach token [dict get $model tokens] {if {[dict get $token category] eq {string}} {set stringToken $token}}
check {[dict get $model bytes]==[string length [encoding convertto utf-8 $source]]} canonical_utf8_byte_count
check {[dict get $stringToken byte_start]==4 && [dict get $stringToken byte_end]==10} canonical_utf8_token_offsets
check {[dict get $stringToken end]-[dict get $stringToken start]==4} tk_utf16_source_positions
foreach {language code expected} {
 python {# comment
@decorator
def f(x):
    """literal # not comment"""
    return x + 2.5
} {comment decorator keyword definition string number}
 octave {% comment
function y = f(x)
  if x > 0
    y = x(end);
  endif
endfunction
} {comment keyword definition number}
 javascript {/* inert */ const value = "literal"; function f(x) { return x + 2; }} {comment keyword string number}
 c {/* inert */ int f(void) { return 2; }} {comment keyword number}
 fortran {! inert
program measure
 implicit none
 print *, 2.0
endprogram measure
} {comment keyword number}
 perl {# inert
sub f { return "literal"; }} {comment keyword definition string}
 tcl {# inert
proc f {x} {return 2}} {comment keyword definition number}
 tk {# inert
set w "window"} {comment keyword string}
 xml {<!-- inert --><measurement unit="V">3</measurement>} {comment tag attribute string}
 html {<!-- inert --><h1 class="title">Text</h1>} {comment tag attribute string}
 markdown {# Heading
`literal`} {identifier}
} {
 set m [::GX::NativeDocument::scan $language $code];set kinds {}
 foreach t [dict get $m tokens] {lappend kinds [dict get $t category]}
 foreach kind $expected {check {$kind in $kinds} ${language}_$kind}
 if {$language eq {octave}} {check {[llength [dict get $m folds]]==2} octave_index_end_not_fold}
}
set rendered [::GX::NativeDocument::render html {<h1>Visible</h1><script>FORBIDDEN_PAYLOAD</script><p>A &amp; B</p><img src="https://invalid.example" alt="safe alt">}]
check {[string first FORBIDDEN_PAYLOAD $rendered]<0 && [string first Visible $rendered]>=0 && [string first {A & B} $rendered]>=0} native_html_inert_entities
check {[catch {::GX::NativeDocument::render xml {<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><x>&e;</x>}}]} native_xml_xxe_refused
set d [::GX::NativeDocument::xml create laboratory];set r [::GX::NativeDocument::xml root $d]
::GX::NativeDocument::xml attribute $d $r xmlns:q urn:lab
set a [::GX::NativeDocument::xml append $d $r q:measurement "A & B < C $emoji"]
set serialized [::GX::NativeDocument::xml serialize $d 1]
check {[string first {A &amp; B &lt; C} $serialized]>=0} xml_escaped
set round [::GX::NativeDocument::xml parse $serialized]
check {[llength [::GX::NativeDocument::xml query $round [::GX::NativeDocument::xml root $round] measurement]]==1} xml_unicode_namespace_roundtrip
check {[catch {::GX::NativeDocument::xml move $d $r $a}]} xml_cycle_refused
::GX::NativeDocument::xml remove $d $a
check {[catch {::GX::NativeDocument::xml describe $d $a}]} xml_deleted_node_refused
::GX::NativeDocument::xml release $d
check {[catch {::GX::NativeDocument::xml root $d}]} xml_released_document_refused
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS checks $checks unicode_model $model];close $f
puts "PASS [dict size $checks] native contracts"
