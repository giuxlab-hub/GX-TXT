# Controlled, data-only expression grammar; NOT a numerical computation engine.
# Only the public math.numeric service performs mathematical operations.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::MathematicsExplorer {}

proc ::GX::MathematicsExplorer::tokenize {expression} {
    if {[string length $expression] > 180} {error "Expression limit is 180 characters."}
    set rest $expression; set tokens {}
    while {[string trim $rest] ne ""} {
        if {[regexp {^\s+} $rest match]} {
            set rest [string range $rest [string length $match] end]
            continue
        }
        if {[regexp {^([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?} $rest number]} {
            lappend tokens [list number $number]
            set rest [string range $rest [string length $number] end]
        } elseif {[regexp {^[a-zA-Z_][a-zA-Z_0-9]*} $rest identifier]} {
            lappend tokens [list id $identifier]
            set rest [string range $rest [string length $identifier] end]
        } else {
            set ch [string index $rest 0]
            if {$ch ni {+ - * / ^ ( ) ,}} {error "Unsupported character in expression: '$ch'."}
            lappend tokens [list symbol $ch]
            set rest [string range $rest 1 end]
        }
        if {[llength $tokens] > 55} {error "Expression token limit exceeded."}
    }
    lappend tokens [list end ""]
    return $tokens
}

proc ::GX::MathematicsExplorer::_precedence {operator} {
    if {[dict exists {+ 1 - 1 * 2 / 2 ^ 4} $operator]} {return [dict get {+ 1 - 1 * 2 / 2 ^ 4} $operator]}
    return 0
}
proc ::GX::MathematicsExplorer::_peek {tokens index} {
    return [lindex $tokens $index]
}
proc ::GX::MathematicsExplorer::_primary {tokens indexVar depth nodesVar} {
    upvar 1 $indexVar index $nodesVar nodes
    if {$depth > 24 || $nodes > 32} {error "Expression nesting limit exceeded."}
    lassign [_peek $tokens $index] kind value
    incr index
    if {$kind eq "number"} {
        set number [finiteNumber $value "numeric literal"]
        incr nodes
        return [list constant $number]
    }
    if {$kind eq "id"} {
        set name [string tolower $value]
        if {$name in {x a b c}} {
            incr nodes
            return [list symbol $name]
        }
        if {$name eq "pi"} {
            incr nodes
            return [list constant 3.141592653589793]
        }
        if {$name ni {sin cos tan exp log log10 sqrt abs}} {
            error "Unknown function or symbol '$value'. Allowed: x, a, b, c, pi, sin, cos, tan, exp, log, log10, sqrt, abs."
        }
        lassign [_peek $tokens $index] tokenType tokenValue
        if {$tokenType ne "symbol" || $tokenValue ne "("} {error "Expected '(' after $name."}
        incr index
        set argument [_expression $tokens index 1 [expr {$depth+1}] nodes]
        lassign [_peek $tokens $index] tokenType tokenValue
        if {$tokenType ne "symbol" || $tokenValue ne ")"} {error "Expected ')' after argument to $name."}
        incr index
        incr nodes
        return [list function $name $argument]
    }
    if {$kind eq "symbol" && $value eq "("} {
        set inside [_expression $tokens index 1 [expr {$depth+1}] nodes]
        lassign [_peek $tokens $index] tokenType tokenValue
        if {$tokenType ne "symbol" || $tokenValue ne ")"} {error "Missing ')' in expression."}
        incr index
        return $inside
    }
    if {$kind eq "symbol" && $value in {+ -}} {
        # Conventional precedence: -x^2 is -(x^2).
        set rhs [_expression $tokens index 3 [expr {$depth+1}] nodes]
        incr nodes
        return [list unary $value $rhs]
    }
    error "Expected a value, variable, or function argument."
}
proc ::GX::MathematicsExplorer::_expression {tokens indexVar minPrec depth nodesVar} {
    upvar 1 $indexVar index $nodesVar nodes
    if {$depth > 24 || $nodes > 32} {error "Expression nesting limit exceeded."}
    set lhs [_primary $tokens index [expr {$depth+1}] nodes]
    while {1} {
        lassign [_peek $tokens $index] kind value
        if {$kind ne "symbol" || $value ni {+ - * / ^}} {break}
        set prec [_precedence $value]
        if {$prec < $minPrec} {break}
        incr index
        # Exponentiation associates right; other binary operators associate left.
        set rhs [_expression $tokens index [expr {$value eq "^" ? $prec : $prec+1}] [expr {$depth+1}] nodes]
        set lhs [list binary $value $lhs $rhs]
        incr nodes
    }
    return $lhs
}
proc ::GX::MathematicsExplorer::parseExpression {source} {
    set tokens [tokenize $source]
    set index 0; set nodes 0
    set ast [_expression $tokens index 1 0 nodes]
    lassign [_peek $tokens $index] kind value
    if {$kind ne "end"} {error "Unexpected trailing token '$value'."}
    if {$nodes > 32} {error "Expression complexity limit exceeded."}
    return $ast
}
