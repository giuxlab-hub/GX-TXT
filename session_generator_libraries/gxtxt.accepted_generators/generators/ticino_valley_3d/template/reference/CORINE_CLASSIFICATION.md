# CORINE class interpretation
The `Code_18` field is the source 2018 three-digit class code. The bundled official *CORINE Land Cover Product User Manual* provides full nomenclature and class descriptions; no codes were assigned manually.

For later area-weighted fractions, intersect the source polygons with each target cell and use metric intersection area. Suggested **explicit, disjoint** aggregates:

| Fraction | Included official CLC codes | Meaning |
|---|---|---|
| built/artificial | 111,112,121,122,123,124,131,132,133,141,142 | CLC level 1 artificial surfaces |
| forest | 311,312,313 | Broad-leaved, coniferous, mixed forest only |
| agriculture | 211,212,213,221,222,223,231,241,242,243,244 | CLC level 2 agricultural areas |
| water | 511,512 | Water courses and water bodies |

Shrub/grass/natural land (32x/33x), wetlands (4xx), and other coastal classes (521–523) are intentionally **not** silently reassigned to forest/water; track them as other or separately. A single CLC polygon has one categorical class, so fractions are derived later from polygon area, never from invented intermediate values. See official manual for complete 44-class nomenclature.
