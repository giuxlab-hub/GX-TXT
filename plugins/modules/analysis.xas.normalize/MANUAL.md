# XAS normalization — Manual

## Workflow

For each spectrum:

1. convert the energy coordinate internally to eV through the public Unit
   Registry helper;
2. determine `E0` manually or from the maximum of a smoothed numerical
   derivative;
3. select pre-edge and post-edge ranges;
4. fit a linear pre-edge;
5. fit a post-edge polynomial of order 0, 1 or 2;
6. calculate the edge step from the post-edge-minus-pre-edge value at `E0`;
7. calculate normalized `mu(E)`;
8. optionally calculate the flattened representation.

The implementation follows the documented Athena/Larch normalization model,
but is an independent GX-TXT implementation built from public framework
services.

## Automatic ranges

Blank range fields request adaptive defaults based on the available energy
range around `E0`, following the practical Larch-style rules:

- pre-edge lower bound is based on the source minimum rounded to 5 eV;
- pre-edge upper bound defaults to half of that negative offset;
- post-edge upper bound is based on the source maximum rounded to 5 eV;
- post-edge lower bound is derived from the available post-edge width;
- automatic post-edge polynomial order is 0 for <30 eV, 1 for <300 eV, and 2
  otherwise.

All effective values are written to the diagnostics Dataset and report.

## Family failures

`skip_with_report` is intended for real experimental families in which an
individual member may be unusable. Failed members are never silently replaced:
they are excluded from the derived family and recorded with `FAIL` plus the
actual diagnostic. Choose `error` to reject the whole analysis instead.

## Outputs

- normalized/flattened `spectrum.scientific` or `spectrum.family`;
- `<output_dataset_id>.diagnostics` as `table.generic`;
- `xas_normalization_report.txt`;
- `xas_normalization_diagnostics.csv`.

Plotting is intentionally not implemented here. Use `viewer.xas_spectra`, which
delegates to the public `plot.dataset` service.
