"""Inert Python AST folding; never import or execute the source."""
# SPDX-License-Identifier: GPL-3.0-or-later
import ast,sys,dis,types
source=sys.stdin.read(4194305)
if len(source)>4194304:raise ValueError('Source exceeds folding budget')
try:tree=ast.parse(source.removeprefix('\ufeff'))
except (SyntaxError,ValueError,RecursionError):print('folds {} executable_lines {}');raise SystemExit(0)
folds=set()
for node in ast.walk(tree):
    if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef,ast.If,ast.For,ast.AsyncFor,ast.While,ast.Try,ast.With,ast.AsyncWith,ast.ExceptHandler,ast.Match)):
        first=node.lineno;last=getattr(node,'end_lineno',first)
        if last>first:folds.add((first,last))
lines=set()
def instructions(code):
    lines.update(n for _,n in dis.findlinestarts(code) if n>0)
    for value in code.co_consts:
        if isinstance(value,types.CodeType):instructions(value)
try:instructions(compile(tree,'<source presentation>','exec',dont_inherit=True))
except (SyntaxError,ValueError,RecursionError):pass
print('folds {%s} executable_lines {%s}'%(' '.join('{%d %d}'%f for f in sorted(folds)), ' '.join(map(str,sorted(lines)))))
