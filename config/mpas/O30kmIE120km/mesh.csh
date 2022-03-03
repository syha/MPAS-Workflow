#!/bin/csh -f

# Uniform 30km mesh -- forecast, hofx, variational outer loop
# Uniform 120km mesh -- variational inner loop

setenv MPASGridDescriptorOuter 30km
setenv MPASGridDescriptorInner 120km
setenv MPASGridDescriptorEnsemble ${MPASGridDescriptorInner}
setenv MPASnCellsOuter 655362
setenv MPASnCellsInner 40962
setenv MPASnCellsEnsemble ${MPASnCellsInner}
setenv MPASTimeStep 180.0
setenv MPASDiffusionLengthScale 30000.0
setenv RADTHINDISTANCE    "60.0"
setenv RADTHINAMOUNT      "0.75"

## ABI super-obbing footprint, set independently
#  for variational and hofx
#OPTIONS: 15X15, 59X59
set variationalABISuperOb = 15X15
set hofxABISuperOb = 15X15

## AHI super-obbing footprint set independently
#  for variational and hofx
#OPTIONS: 15X15, 101X101
set variationalAHISuperOb = 15X15
set hofxAHISuperOb = 15X15

## Background Error

### Ensemble localization

#### strategy: common

#### 1200km horizontal loc
#### 6km height vertical loc
setenv bumpLocPrefix bumploc_1200.0km_6.0km
setenv bumpLocDir /glade/p/mmm/parc/guerrett/pandac/fixed_input/120km/bumploc/h=1200.0km_v=6.0km_28FEB2022code
