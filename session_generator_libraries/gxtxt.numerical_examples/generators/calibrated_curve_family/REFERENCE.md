# Independent analytical reference

These are source definitions, not results computed by a GX-TXT Analysis module.
Use integer c∈[0,49], i∈[0,299], k∈[0,4], with rational t=i/299.

An independent reconstruction can avoid the producer's pixel-to-physical
evaluation order by using:

    u = (29900 +1000i)/299
    q = (2i−299)²/299²
    v = 900−14c−8q
    x = 10(1+k/1000)i/299 +k/100
    y = (14c+8q)(1−k/2000)/100 −k/200

All coefficients and source values are rational before float64 serialization.
The independent validation helper reconstructs them with fractions.Fraction,
without importing generator code or treating generated truth as an oracle.
Use a documented floating arithmetic bound when comparing decimalized float64
coordinates; that roundoff bound is not a measurement uncertainty or fit tolerance.

For each k, the2×3 homogeneous affine map on [u,v,1] is:

    [(1000+k)/100000, 0, −1+9k/1000]
    [0, −(2000−k)/200000, 9−19k/2000]

Both diagonal entries are nonzero. Every point sharing k uses the same map;
there are no point-specific fitted coefficients or independence claims.
`reference_spec.json` gives three hand-checkable rational anchors. For example
c=49,i=299,k=4 gives u=1100,v=206,x=10.08s,y=6.90612V.

The reference overlay adds0.5 to u/v when expressing SVG pixel-cell positions.
PNG lines join nearest integer pixel-center indices. Exact source coordinates
remain in CSV; image rounding is a presentation derivative and never replaces
the mathematical observations.

Actual generated counts, public schema readback and numerical parity must be
verified separately. No source reference, helper success or static image is a
genuine-GUI or performance acceptance receipt.
