# NUMERIC_API_v1 Tcl examples. The public entrypoint must already be sourced.
# SPDX-License-Identifier: GPL-3.0-or-later
set p [::GX::NumericAPIv1::polynomialFit {0 1 2 3} {1 6 17 34} 2]
set pw [::GX::NumericAPIv1::polynomialFit {0 1 2 3} {1 6 17 34} 2 {1 1 2 2}]
set s [::GX::NumericAPIv1::splineCreate {0 1 2 3} {0 1 4 9} [dict create method pchip]]
set se [::GX::NumericAPIv1::splineEvaluate $s {0.5 1.5 2.5}]
set smooth [::GX::NumericAPIv1::smooth {0 1 2 3 4} {0 1 5 1 0} [dict create method moving_mean window 3]]
# Dataset examples:
# set r [::GX::NumericAPIv1::resampleUniformDataset $session $datasetId $xId $yId 0.001 [dict create method pchip]]
# set i [::GX::NumericAPIv1::integrateDataset $session $datasetId $xId $yId [dict create selection_id $selectionId]]
# set d [::GX::NumericAPIv1::differentiateDataset $session $datasetId $xId $yId]
# set st [::GX::NumericAPIv1::statisticsDataset $session $datasetId $yId [dict create selection_id $selectionId]]
