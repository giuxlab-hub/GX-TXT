// Original equations retained; explicit GetDP residual instrumentation. GPL-3.0-or-later.
static const char* integration = R"EM_TEMPLATE(
Jacobian { { Name Vol; Case { { Region All; Jacobian Vol; } } } }
Integration {
  { Name GradGrad; Case { { Type Gauss; Case { { GeoElement Triangle; NumberOfPoints 4; } } } } }
  { Name CurlCurl; Case { { Type Gauss; Case { { GeoElement Triangle; NumberOfPoints 4; } } } } }
}
)EM_TEMPLATE";
static const char* electro_pro = R"EM_TEMPLATE(// Linear 2D electrostatics, H1 potential. Based on GetDP EleSta_v.
Group {
  Dielectric = Region[101]; Low = Region[120]; High = Region[121];
  DomainCC_Ele = Region[{Dielectric}];
}
Function { epsr[Dielectric] = @EPS@; }
Constraint {
  { Name ElectricScalarPotential; Type Assign;
    Case { { Region Low; Value 0.; } { Region High; Value @VOLTAGE@; } }
  }
}
@INTEGRATION@
FunctionSpace {
 { Name Hgrad_v_Ele; Type Form0;
   BasisFunction { { Name sn; NameOfCoef vn; Function BF_Node;
                     Support DomainCC_Ele; Entity NodesOf[All]; } }
   Constraint { { NameOfCoef vn; EntityType NodesOf;
                  NameOfConstraint ElectricScalarPotential; } }
 }
}
Formulation {
 { Name Electrostatics_v; Type FemEquation;
   Quantity { { Name v; Type Local; NameOfSpace Hgrad_v_Ele; } }
   Equation { Galerkin { [ epsr[] * Dof{d v}, {d v} ]; In DomainCC_Ele;
                         Jacobian Vol; Integration GradGrad; } }
 }
}
Resolution {
 { Name SolveEle; System { { Name Sys_Ele; NameOfFormulation Electrostatics_v; } }
   Operation { Generate[Sys_Ele]; Solve[Sys_Ele]; Generate[Sys_Ele]; GetResidual[Sys_Ele, $emres]; Print[{$emres}, Format "GXTXT_RESIDUAL %.17g"]; SaveSolution[Sys_Ele]; }
 }
}
PostProcessing {
 { Name PostEle; NameOfFormulation Electrostatics_v;
   Quantity {
      { Name v; Value { Local { [ {v} ]; In DomainCC_Ele; Jacobian Vol; } } }
      { Name e; Value { Local { [ -{d v} ]; In DomainCC_Ele; Jacobian Vol; } } }
   }
 }
}
PostOperation {
 { Name MapEle; NameOfPostProcessing PostEle;
   Operation {
      Print[ v, OnElementsOf DomainCC_Ele, File "V.pos" ];
      Print[ e, OnElementsOf DomainCC_Ele, File "E.pos" ];
   }
 }
}
)EM_TEMPLATE";
static const char* magnetic_pro = R"EM_TEMPLATE(// Linear 2D magnetostatics, out-of-plane A_z, real current source.
// Based on the official GetDP MagSta_a_2D formulation.
Group {
 Air = Region[101]; Ind = Region[102]; Boundary = Region[110];
 Domain_Mag = Region[{Air,Ind}]; DomainS_Mag = Region[{Ind}];
}
Function { nu[Air] = 1. / (4.e-7 * Pi);
           nu[Ind] = 1. / (4.e-7 * Pi * @MU@); }
Constraint {
 { Name MagneticVectorPotential_2D; Type Assign;
   Case { { Region Boundary; Value 0.; } } }
 { Name SourceCurrentDensityZ; Type Assign;
   Case { { Region Ind; Value @CURRENT@; } } }
}
@INTEGRATION@
FunctionSpace {
 { Name Hcurl_a_Mag_2D; Type Form1P;
   BasisFunction { { Name se; NameOfCoef ae; Function BF_PerpendicularEdge;
                      Support Domain_Mag; Entity NodesOf[All]; } }
   Constraint { { NameOfCoef ae; EntityType NodesOf;
                  NameOfConstraint MagneticVectorPotential_2D; } }
 }
 { Name Hregion_j_Mag_2D; Type Vector;
   BasisFunction { { Name sr; NameOfCoef jsr; Function BF_RegionZ;
                      Support DomainS_Mag; Entity DomainS_Mag; } }
   Constraint { { NameOfCoef jsr; EntityType Region;
                  NameOfConstraint SourceCurrentDensityZ; } }
 }
}
Formulation {
 { Name Magnetostatics_a_2D; Type FemEquation;
   Quantity {
      { Name a; Type Local; NameOfSpace Hcurl_a_Mag_2D; }
      { Name js; Type Local; NameOfSpace Hregion_j_Mag_2D; }
   }
   Equation {
      Galerkin { [ nu[] * Dof{d a}, {d a} ]; In Domain_Mag;
                 Jacobian Vol; Integration CurlCurl; }
      Galerkin { [ -Dof{js}, {a} ]; In DomainS_Mag;
                 Jacobian Vol; Integration CurlCurl; }
   }
 }
}
Resolution {
 { Name SolveMag; System { { Name Sys_Mag; NameOfFormulation Magnetostatics_a_2D; } }
   Operation { Generate[Sys_Mag]; Solve[Sys_Mag]; Generate[Sys_Mag]; GetResidual[Sys_Mag, $emres]; Print[{$emres}, Format "GXTXT_RESIDUAL %.17g"]; SaveSolution[Sys_Mag]; }
 }
}
PostProcessing {
 { Name PostMag; NameOfFormulation Magnetostatics_a_2D;
   Quantity {
      { Name az; Value { Local { [ CompZ[{a}] ]; In Domain_Mag; Jacobian Vol; } } }
      { Name b; Value { Local { [ {d a} ]; In Domain_Mag; Jacobian Vol; } } }
      { Name h; Value { Local { [ nu[] * {d a} ]; In Domain_Mag; Jacobian Vol; } } }
   }
 }
}
PostOperation {
 { Name MapMag; NameOfPostProcessing PostMag;
   Operation {
      Print[ az, OnElementsOf Domain_Mag, File "Az.pos" ];
      Print[ b, OnElementsOf Domain_Mag, File "B.pos" ];
      Print[ h, OnElementsOf Domain_Mag, File "H.pos" ];
   }
 }
}
)EM_TEMPLATE";
