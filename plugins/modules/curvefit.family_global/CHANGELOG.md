# Changelog

SPDX-License-Identifier: GPL-3.0-or-later

# Version 6

- Resolve primary Analysis Source binding prefixes before matching the
  Dataset CSV header in a normal GUI run.

## Distribution note — GX-TXT v0.9.7.2
- Promoted `curvefit.family_global` plugin version 4 to protected `CORE / OFF` distribution status.
- No scientific algorithm, solver, fitting, model-domain, graph-provider, or output behavior changed.

## Plugin version 4
- Added fit/evaluate operation modes with frozen-parameter evaluation.
- Uses shared Parameter-Set API and Model-Domain API.
- Reports progress through Progress API v1 and retains standard Graph Provider outputs.
# 5

- Published canonical fitting and validation Datasets and rendered all five graphs as persistent public Plot.dataset variants. Bound optimization to CORE `NUMERIC_API_v1` with the explicit bounded fallback; the module no longer owns a generic nonlinear solver or a private graphics renderer.
