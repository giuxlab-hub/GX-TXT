# Shockley diode with series resistance

`diode.shockley_series_v1` solves the ideal diode equation
`I = Is*expm1((V-I*Rs)/Vt)`. Inputs must declare V and responses A. Is is a
positive saturation current, Vt a positive effective thermal voltage `n*k*T/q`,
and Rs a nonnegative resistance in V/A. Vt does not identify temperature and
ideality factor separately. No breakdown, shunt leakage or self-heating is
included. Existing triode models retain their separate scientific identities.

The Numeric-owned expression function `shockley_series` evaluates the unique
monotone solution using `u + (Rs*Is/Vt)*expm1(u) = V/Vt`. Bounded safeguarded
Newton steps evaluate this implicit function; fitting still uses the one shared
Ceres optimizer. `expm1` preserves near-zero current and intermediate long-double
arithmetic avoids overflow in finite double parameter ratios. Unrepresentable
outputs reject. The Rs=0 limit uses the explicit diode equation.

With `g=Is*exp(u)/Vt` and `D=1+Rs*g`, the analytic derivatives are
`dI/dV=g/D`, `dI/dIs=expm1(u)/D`, `dI/dVt=-g*u/D`, and `dI/dRs=-g*I/D`.
These physical derivatives feed the shared automatic-differentiation program
and covariance calculation. CORE controls statistical interpretation; no
statistics are computed by this descriptor. Active Rs=0 constraints make
ordinary unconstrained intervals unavailable.

Fitter translations are forbidden. Explicitly convert measured mV/mA data before
binding; do not relabel them. Review parameter scales, data range and noise
semantics. All declarations, constraints, units and source hashes are frozen in
accepted model state and Script publications.
