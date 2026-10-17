"""Inert Python AST folding; never import or execute the source."""
# SPDX-License-Identifier: GPL-3.0-or-later
import ast,sys
source=sys.stdin.read(4194305)
if len(source)>4194304:raise ValueError('Source exceeds folding budget')
try:tree=ast.parse(source)
except (SyntaxError,ValueError,RecursionError):print('');raise SystemExit(0)
folds=set()
for node in ast.walk(tree):
    if isinstance(node,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef,ast.If,ast.For,ast.AsyncFor,ast.While,ast.Try,ast.With,ast.AsyncWith,ast.ExceptHandler,ast.Match)):
        first=node.lineno;last=getattr(node,'end_lineno',first)
        if last>first:folds.add((first,last))
print(' '.join('{%d %d}'%f for f in sorted(folds)))
