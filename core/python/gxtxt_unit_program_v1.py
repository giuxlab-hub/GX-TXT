"""Unit Registry v1 program decoder/evaluator for CORE bulk consumers.

There is no second formula parser: Tcl Unit Registry supplies the parsed tree.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import math
import operator

_OPS = {"+": operator.add, "-": operator.sub, "*": operator.mul,
        "/": operator.truediv, "^": math.pow, "unary+": operator.pos,
        "unary-": operator.neg, "log": math.log, "log10": math.log10,
        "exp": math.exp, "sqrt": math.sqrt}
_ARITY = {key: 2 if key in ("+", "-", "*", "/", "^") else 1 for key in _OPS}


def decode_program(host, raw):
    program = host.as_dict(raw)
    if int(program["program_version"]) != 1:
        raise ValueError("Unsupported Unit Registry formula program")
    count = 0
    def decode(value, depth=0):
        nonlocal count
        count += 1
        if depth > 64 or count > 4096:
            raise ValueError("Unit formula program exceeds bounded complexity")
        node = host.as_list(value)
        if not node:
            raise ValueError("Empty unit program node")
        op = str(node[0])
        if op == "x" and len(node) == 1:
            return [op]
        if op == "number" and len(node) == 2:
            value = float(node[1])
            if not math.isfinite(value):
                raise ValueError("Unit program constants must be finite")
            return [op, value]
        if op not in _OPS or len(node) != _ARITY[op] + 1:
            raise ValueError("Invalid unit program operation")
        return [op] + [decode(child, depth + 1) for child in node[1:]]
    return dict(program_version=1, tree=decode(program["tree"]))


def compile_formula(host, formula):
    program = decode_program(host, host.call("::GX::unitFormulaProgram", formula))
    def compile_node(node):
        op = node[0]
        if op == "x":
            return lambda x: x
        if op == "number":
            return lambda x: node[1]
        children = [compile_node(child) for child in node[1:]]
        operation = _OPS[op]
        def evaluate(x):
            value = operation(*(child(x) for child in children))
            if math.isfinite(x) and not math.isfinite(value):
                raise ValueError("Unit formula exceeds the finite numeric range")
            return value
        return evaluate
    evaluate = compile_node(program["tree"])
    def converted(value):
        if isinstance(value, int) and int(float(value)) != value:
            raise ValueError("Unit conversion would lose input integer precision")
        return evaluate(float(value))
    return converted
