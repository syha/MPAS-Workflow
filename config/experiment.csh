#!/bin/csh -f

source config/appindex.csh

##################################
## Fundamental experiment settings
##################################
## MPASGridDescriptor
# used to distinguish betwen MPAS meshes across experiments
# OPTIONS:
#   + 120km 3denvar
#   + 120km eda_3denvar
#   + TODO: "30km" 3denvar
#   + TODO: "30km-120km" dual-resolution 3denvar
#   + TODO: "30km-120km" dual-resolution eda_3denvar
#   + TODO: "120km" 4denvar
#   + TODO: "30km-120km" dual-resolution 4denvar
setenv MPASGridDescriptor 120km

## FirstCycleDate
# initial date of this experiment
# OPTIONS:
#   + 2018041500
#   + 2020072300 --> experimental
#     - TODO: standardize GFS and observation source data
#     - TODO: enable QC
#     - TODO: enable VarBC
setenv FirstCycleDate 2018041500

## benchmarkObsList
# base set of observation types assimilated in all experiments
set benchmarkObsList = (sondes aircraft satwind gnssroref sfcp clramsua)

## benchmarkDAType
# base data assimilation type to which others are compared
set benchmarkDAType = 3denvar

## ExpSuffix
# a unique suffix to distinguish this experiment from others
set ExpSuffix = ''

##############
## DA settings
##############
# add IR super-obbing resolution suffixes for variational
set abi = abi$ABISuperOb[$variationalIndex]
set ahi = ahi$AHISuperOb[$variationalIndex]

## variationalObsList
# OPTIONS: $benchmarkObsList, cldamsua, clr$abi, all$abi, clr$ahi, all$ahi
# clr == clear-sky
# cld == cloudy-sky
# all == all-sky
#TODO: separate amsua and mhs config for each instrument_satellite combo

set variationalObsList = ($benchmarkObsList)
#set variationalObsList = ($benchmarkObsList cldamsua)
#set variationalObsList = ($benchmarkObsList all$abi)
#set variationalObsList = ($benchmarkObsList all$ahi)
#set variationalObsList = ($benchmarkObsList all$abi all$ahi)

## DAType
# OPTIONS: 3denvar, eda_3denvar, 3dvarId
setenv DAType 3denvar

if ( "$DAType" =~ *"eda"* ) then
  ## nEnsDAMembers
  # OPTIONS: 2 to $firstEnsFCNMembers, depends on data source in config/data.csh
  setenv nEnsDAMembers 20
else
  setenv nEnsDAMembers 1
endif

## LeaveOneOutEDA
# OPTIONS: True/False
setenv LeaveOneOutEDA True

## RTPPInflationFactor
# Typical Values: 0.0 or 0.50 to 0.90
setenv RTPPInflationFactor 0.0

## ABEIInflation
# OPTIONS: True/False
setenv ABEInflation False

## ABEIChannel
# OPTIONS: 8, 9, 10
setenv ABEIChannel 8

################
## HofX settings
################
# add IR super-obbing resolution suffixes for hofx
set abi = abi$ABISuperOb[$hofxIndex]
set ahi = ahi$AHISuperOb[$hofxIndex]

## hofxObsList
# OPTIONS: $benchmarkObsList, cldamsua, allmhs, clr$abi, all$abi, clr$ahi, all$ahi
#TODO: separate amsua and mhs config for each instrument_satellite combo

set hofxObsList = ($benchmarkObsList cldamsua allmhs all$abi all$ahi)


#GEFS reference case (override above settings)
#====================================================
#set ExpSuffix = _GEFSVerify
#setenv DAType eda_3denvar
#setenv nEnsDAMembers 20
#setenv RTPPInflationFactor 0.0
#setenv LeaveOneOutEDA False
#set variationalObsList = ($benchmarkObsList)
#====================================================

##################################
## analysis and forecast intervals
##################################
setenv CyclingWindowHR 6                # forecast interval between CyclingDA analyses
setenv ExtendedFCWindowHR 240           # length of verification forecasts
setenv ExtendedFC_DT_HR 12              # interval between OMF verification times of an individual forecast
setenv ExtendedMeanFCTimes T00,T12      # times of the day to run extended forecast from mean analysis
setenv ExtendedEnsFCTimes T00           # times of the day to run ensemble of extended forecasts
setenv DAVFWindowHR ${CyclingWindowHR}  # window of observations included in AN/BG verification
setenv FCVFWindowHR 6                   # window of observations included in forecast verification


########################
## experiment name parts
########################

## derive experiment title parts from above settings

#(1) populate ensemble-related suffix components
set EnsExpSuffix = ''
if ($nEnsDAMembers > 1) then
  set EnsExpSuffix = '_NMEM'${nEnsDAMembers}
  if (${RTPPInflationFactor} != "0.0") set EnsExpSuffix = ${EnsExpSuffix}_RTPP${RTPPInflationFactor}
  if (${LeaveOneOutEDA} == True) set EnsExpSuffix = ${EnsExpSuffix}_LeaveOneOut
  if (${ABEInflation} == True) set EnsExpSuffix = ${EnsExpSuffix}_ABEI_BT${ABEIChannel}
endif

#(2) add observation selection info
setenv ExpObsName ''
foreach obs ($variationalObsList)
  set isBench = False
  foreach benchObs ($benchmarkObsList)
    if ("$obs" =~ *"$benchObs"*) then
      set isBench = True
    endif
  end
  if ( $isBench == False ) then
    setenv ExpObsName ${ExpObsName}_${obs}
  endif
end

##########################
## run directory structure
##########################
## absolute experiment directory
setenv PKGBASE MPAS-Workflow
setenv ExperimentUser ${USER}
setenv TOP_EXP_DIR /glade/scratch/${ExperimentUser}/pandac
setenv ExperimentName ${ExperimentUser}
setenv ExperimentName ${ExperimentName}_${DAType}
setenv ExperimentName ${ExperimentName}${ExpObsName}
setenv ExperimentName ${ExperimentName}${EnsExpSuffix}
setenv ExperimentName ${ExperimentName}_${MPASGridDescriptor}
setenv ExperimentName ${ExperimentName}${ExpSuffix}

setenv EXPDIR ${TOP_EXP_DIR}/${ExperimentName}
setenv TMPDIR /glade/scratch/${USER}/temp
mkdir -p $TMPDIR

## immediate subdirectories
setenv CyclingDAWorkDir ${EXPDIR}/CyclingDA
setenv CyclingFCWorkDir ${EXPDIR}/CyclingFC
setenv CyclingInflationWorkDir ${EXPDIR}/CyclingInflation
setenv ExtendedFCWorkDir ${EXPDIR}/ExtendedFC
setenv VerificationWorkDir ${EXPDIR}/Verification

## directories copied from PKGBASE
setenv mainScriptDir ${EXPDIR}/${PKGBASE}
setenv ConfigDir ${mainScriptDir}/config
set ModelConfigDir = ${ConfigDir}/mpas
setenv forecastModelConfigDir ${ModelConfigDir}/forecast
setenv hofxModelConfigDir ${ModelConfigDir}/hofx
if ($nEnsDAMembers > 1 && ${ABEInflation} == True) then
  setenv variationalModelConfigDir ${ModelConfigDir}/variational-bginflate
else
  setenv variationalModelConfigDir ${ModelConfigDir}/variational
endif
setenv rtppModelConfigDir ${ModelConfigDir}/rtpp

## workflow tools
set pyDir = ${mainScriptDir}/tools
set pyTools = (memberDir advanceCYMDH nSpaces)
foreach tool ($pyTools)
  setenv ${tool} "python ${pyDir}/${tool}.py"
end
