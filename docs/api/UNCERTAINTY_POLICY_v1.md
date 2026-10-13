# Uncertainty propagation policy v1

SPDX-License-Identifier: GPL-3.0-or-later

**Defined:** GX-TXT Pipeline v0.8.4  
**Status:** policy/contract; generalized propagation implementation is deferred.

## Principle

GX-TXT must never manufacture a numeric uncertainty simply because a scientific value can be computed. An uncertainty output is valid only when the operation declares a supported propagation rule and all required uncertainty inputs are available.

An uncertainty series is an ordinary row-aligned numeric variable with semantic role:

```ini
role=uncertainty
```

For example:

```ini
[variable.sigma_y]
source=primary
binding=sigma_y
type=numeric
role=uncertainty
required=0
```

v0.8.4 continues to preserve such data through transformations where rows remain aligned, but does not silently apply a universal error formula.

## Required future status behavior

When an operation requests uncertainty propagation, the result must use the standard status model:

```text
valid
warning
unavailable
failed
```

Recommended machine-readable reasons include:

```text
uncertainty_input_missing
uncertainty_rule_unsupported
uncertainty_dependency_unavailable
invalid_uncertainty
```

A missing/unsupported uncertainty result must not invalidate an otherwise valid nominal scientific result unless the definition explicitly declares uncertainty as required.

## Planned propagation families

The framework-level implementation should cover, in order:

1. independent first-order propagation for simple arithmetic expressions;
2. aggregate/statistical uncertainty where assumptions are explicitly declared;
3. interpolation uncertainty;
4. crossing/feature uncertainty;
5. fit/regression covariance or equivalent diagnostics when provided by the selected method/model.

## Assumptions must be explicit

The framework must not assume independence, normality, identical variance, covariance structure, or confidence level without definition metadata or an operation-specific documented default.

## v0.8.4 implementation boundary

v0.8.4 provides this policy and preserves uncertainty inputs. General propagation is intentionally listed in `TODO_v085.md` rather than being implemented ad hoc inside individual operations or plugins.
