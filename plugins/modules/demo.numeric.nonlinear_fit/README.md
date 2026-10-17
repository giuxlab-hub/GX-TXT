# Nonlinear fit integration demo

`demo.numeric.nonlinear_fit` is an external GX-TXT analysis plugin for the
`GX-TXT Numerical Examples / Nonlinear Fitting` generated Session.

Version 1.1.0 uses the declared Numeric Ceres model `A*exp(-k*x)+c` and the public CORE statistical interpretation API. Parameter identities remain `A`, `k`, `c`; source bindings, output Dataset `demo.nonlinear.fit`, existing report keys and graph IDs are preserved.

The generated CSV is imported normally through `acq.generic_csv`. Choose that Dataset as source `primary`, then bind `primary.x` and `primary.y`. The runtime resolves their stable variable IDs. Reference parameters are read from the generated Session's `metadata/ground_truth.txt`.

CORE supplies parameter units, covariance/SE interpretation and validated report text. The legacy `rmse` key retains Numeric's residual-DOF-scaled standard deviation, with an explicit quantity identity and status. Generator prose is retained as provenance and does not establish an inferential noise assumption.

See `MANUAL.md` for the exact GUI procedure.

Target framework: GX-TXT 0.9.8.10-dev-097 with the platform Numeric Ceres backend.
