#!/bin/csh -f

#TODO: move this script functionality and relevent control's to python + maybe yaml

# Perform preparation for the variational application
# + iterations
# + ensemble Jb term
# + TODO: static Jb term

date

# Process arguments
# =================
## args
# ArgMember: int, ensemble member [>= 1]
# note: not currently used, but will be for independent EDA members
set ArgMember = "$1"

## arg checks
set test = `echo $ArgMember | grep '^[0-9]*$'`
set isNotInt = ($status)
if ( $isNotInt ) then
  echo "ERROR in $0 : ArgMember ($ArgMember) must be an integer" > ./FAIL
  exit 1
endif
if ( $ArgMember < 1 ) then
  echo "ERROR in $0 : ArgMember ($ArgMember) must be > 0" > ./FAIL
  exit 1
endif

# Setup environment
# =================
source config/environment.csh
source config/experiment.csh
source config/filestructure.csh
source config/tools.csh
source config/modeldata.csh
source config/mpas/variables.csh
source config/mpas/${MPASGridDescriptor}/mesh.csh
set yymmdd = `echo ${CYLC_TASK_CYCLE_POINT} | cut -c 1-8`
set hh = `echo ${CYLC_TASK_CYCLE_POINT} | cut -c 10-11`
set thisCycleDate = ${yymmdd}${hh}
set thisValidDate = ${thisCycleDate}
source ./getCycleVars.csh

# static work directory
set self_WorkDir = $CyclingDADirs[1]
echo "WorkDir = ${self_WorkDir}"
cd ${self_WorkDir}

# other static variables
set self_WindowHR = ${CyclingWindowHR}
set self_StateDirs = ($prevCyclingFCDirs)
set self_StatePrefix = ${FCFilePrefix}
set StreamsFileList = (${variationalStreamsFileList})

# Remove old netcdf lock files
rm *.nc*.lock

# Remove old static fields in case this directory was used previously
rm ${localStaticFieldsPrefix}*.nc*

# ==================================================================================================

# ============================
# Variational YAML preparation
# ============================

echo "Starting YAML preparation stage"

# Previous time info for yaml entries
# ===================================
set prevValidDate = `$advanceCYMDH ${thisValidDate} -${self_WindowHR}`

# Rename appyaml generated by a previous preparation script
# =========================================================
rm prevPrep.yaml
mv $appyaml prevPrep.yaml
set prevYAML = prevPrep.yaml

# Outer iterations configuration elements
# ===========================================
# performs sed substitution for VariationalIterations
set iterationssed = VariationalIterations
set thisSEDF = ${iterationssed}SEDF.yaml
cat >! ${thisSEDF} << EOF
/${iterationssed}/c\
EOF

set nIterationsIndent = 2
set indent = "`${nSpaces} $nIterationsIndent`"
set iOuter = 0
foreach nInner ($nInnerIterations)
  @ iOuter++
  set nn = ${nInner}
cat >>! ${thisSEDF} << EOF
${indent}- <<: *iterationConfig\
EOF

  if ( $iOuter == 1 ) then
cat >>! ${thisSEDF} << EOF
${indent}  diagnostics:\
${indent}    departures: depbg\
EOF

  endif
  if ( $iOuter < $nOuterIterations ) then
    set nn = $nn\\
  endif
cat >>! ${thisSEDF} << EOF
${indent}  ninner: ${nn}
EOF

end

set thisYAML = insertIterations.yaml
sed -f ${thisSEDF} $prevYAML >! $thisYAML
rm ${thisSEDF}
set prevYAML = $thisYAML


# Minimization algorithm configuration element
# ================================================
# performs sed substitution for VariationalMinimizer
set algorithmsed = VariationalMinimizer
set thisSEDF = ${algorithmsed}SEDF.yaml
cat >! ${thisSEDF} << EOF
/${algorithmsed}/c\
EOF

set nAlgorithmIndent = 4
set indent = "`${nSpaces} $nAlgorithmIndent`"
if ($MinimizerAlgorithm == $BlockEDA) then
cat >>! ${thisSEDF} << EOF
${indent}algorithm: $MinimizerAlgorithm\
${indent}members: $EDASize
EOF

else
cat >>! ${thisSEDF} << EOF
${indent}algorithm: $MinimizerAlgorithm
EOF

endif

set thisYAML = insertAlgorithm.yaml
sed -f ${thisSEDF} $prevYAML >! $thisYAML
rm ${thisSEDF}
set prevYAML = $thisYAML


# Ensemble Jb term
# ================

## ensemble Jb yaml indentation
if ( "$DAType" =~ *"envar"* ) then
  set nEnsPbIndent = 4
else if ( "$DAType" =~ *"hybrid"* ) then
  set nEnsPbIndent = 8
else
  set nEnsPbIndent = 0
endif
set indentPb = "`${nSpaces} $nEnsPbIndent`"

## ensemble Jb localization
sed -i 's@bumpLocDir@'${bumpLocDir}'@g' $prevYAML
sed -i 's@bumpLocPrefix@'${bumpLocPrefix}'@g' $prevYAML

## ensemble Jb inflation
# performs sed substitution for EnsemblePbInflation
set enspbinfsed = EnsemblePbInflation
set thisSEDF = ${enspbinfsed}SEDF.yaml
set removeInflation = 0
if ( "$DAType" =~ *"eda"* && ${ABEInflation} == True ) then
  set inflationFields = ${CyclingABEInflationDir}/BT${ABEIChannel}_ABEIlambda.nc
  find ${inflationFields} -mindepth 0 -maxdepth 0
  if ($? > 0) then
    ## inflation file not generated because all instruments (abi, ahi?) missing at this cylce date
    #TODO: use last valid inflation factors?
    set removeInflation = 1
  else
    set thisYAML = insertInflation.yaml
#NOTE: 'stream name: control' allows for spechum and temperature inflation values to be read
#      read directly from inflationFields without a variable transform. Also requires spechum and
#      temperature to be in stream_list.atmosphere.control.

cat >! ${thisSEDF} << EOF
/${enspbinfsed}/c\
${indentPb}inflation field:\
${indentPb}  date: *analysisDate\
${indentPb}  filename: ${inflationFields}\
${indentPb}  stream name: control
EOF

    sed -f ${thisSEDF} $prevYAML >! $thisYAML
    set prevYAML = $thisYAML
  endif
else
  set removeInflation = 1
endif
if ($removeInflation > 0) then
  # delete the line containing $enspbinfsed
  sed -i '/^'${enspbinfsed}'/d' $prevYAML
endif

## ensemble Jb members
# + pure envar: background error.members
# + hybrid envar: background error.components[iEnsemble].covariance.members
#   where iEnsemble is the ensemble component index of the hybrid B

# performs sed substitution for EnsemblePbMembers
set enspbmemsed = EnsemblePbMembers

# initialize variational member yamls
set yamlFiles = variationals.txt
rm $yamlFiles
set member = 1
while ( $member <= ${nEnsDAMembers} )
  set memberyaml = variational_${member}.yaml
  echo $memberyaml >> $yamlFiles
  cp $prevYAML $memberyaml

  @ member++
end

# substitute Jb members
setenv myCommand "${substituteEnsembleBTemplate} ${ensPbDir}/${prevValidDate} ${ensPbMemPrefix} None ${ensPbFilePrefix}.${fileDate}.nc ${ensPbMemNDigits} ${ensPbNMembers} $yamlFiles ${enspbmemsed} ${nEnsPbIndent} $LeaveOneOutEDA"

echo "$myCommand"
${myCommand}

if ($status != 0) then
  echo "$0 (ERROR): failed to substitute ${enspbmemsed}" > ./FAIL
  exit 1
endif

###################################################################################################
# OLD implementation for individual members in YAML, DEPRECATED
# initialize ensemble Pb member states
#set ensPbFiles = ${enspbmemsed}.txt
#rm $ensPbFiles
#set member = 1
#while ( $member <= ${ensPbNMembers} )
#  set memDir = `${memberDir} ensemble $member "${ensPbMemFmt}"`
#
#  set filename = ${ensPbDir}/${prevValidDate}${memDir}/${ensPbFilePrefix}.${fileDate}.nc
#  echo $filename >> $ensPbFiles
#  @ member++
#end

#setenv myCommand "${substituteEnsembleBMembers} $ensPbFiles $yamlFiles ${enspbmemsed} ${nEnsPbIndent} $LeaveOneOutEDA"
#echo "$myCommand"
#${myCommand}

#rm $ensPbFiles $yamlFiles
###################################################################################################

rm $yamlFiles

# Jo term
# =======

set member = 1
while ( $member <= ${nEnsDAMembers} )
  set memberyaml = variational_${member}.yaml

  # member-specific state I/O and observation file output directory
  set memDir = `${memberDir} $DAType $member`
  sed -i 's@OOPSMemberDir@'${memDir}'@g' $memberyaml

  # first EDA member and deterministic EnVar do not perturb observations
  if ($member == 1) then
    sed -i 's@ObsPerturbations@false@g' $memberyaml
  else
    sed -i 's@ObsPerturbations@true@g' $memberyaml
  endif
  sed -i 's@MemberSeed@'$member'@g' $memberyaml

  @ member++
end

echo "Completed YAML preparation stage"

date

echo "Starting model state preparation stage"

# ====================================
# Input/Output model state preparation
# ====================================

# get source static fields files (config/modeldata.csh)
set StaticFieldsDirList = ($StaticFieldsDirOuter $StaticFieldsDirInner)
set StaticFieldsFileList = ($StaticFieldsFileOuter $StaticFieldsFileInner)

set member = 1
while ( $member <= ${nEnsDAMembers} )
  set memSuffix = `${memberDir} $DAType $member "${flowMemFileFmt}"`

  ## copy static fields
  # unique StaticFieldsDir and StaticFieldsFile for each ensemble member
  # + ensures independent ivgtyp, isltyp, etc...
  # + avoids concurrent reading of StaticFieldsFile by all members
  set iMesh = 0
  foreach localStaticFieldsFile ($variationallocalStaticFieldsFileList)
    @ iMesh++

    set StaticFieldsFile = ${localStaticFieldsFile}${memSuffix}
    rm ${StaticFieldsFile}

    set StaticMemDir = `${memberDir} ens $member "${staticMemFmt}"`
    set memberStaticFieldsFile = $StaticFieldsDirList[$iMesh]${StaticMemDir}/$StaticFieldsFileList[$iMesh]
    ln -sfv ${memberStaticFieldsFile} ${StaticFieldsFile}
  end

  # TODO(JJG): centralize this directory name construction (cycle.csh?)
  set other = $self_StateDirs[$member]
  set bg = $CyclingDAInDirs[$member]
  mkdir -p ${bg}

  # Link bg from StateDirs, ensuring that MPASJEDIDiagVariables are present
  # ============================================================================
  set bgFileOther = ${other}/${self_StatePrefix}.$fileDate.nc
  set bgFile = ${bg}/${BGFilePrefix}.$fileDate.nc

  rm ${bgFile}${OrigFileSuffix} ${bgFile}
  ln -sfv ${bgFileOther} ${bgFile}${OrigFileSuffix}
  ln -sfv ${bgFileOther} ${bgFile}

  # determine analysis output precision
  ncdump -h ${bgFile} | grep uReconstruct | grep double
  if ($status == 0) then
    set analysisPrecision=double
  else
    ncdump -h ${bgFile} | grep uReconstruct | grep float
    if ($status == 0) then
      set analysisPrecision=single
    else
      echo "ERROR in $0 : cannot determine analysis precision" > ./FAIL
      exit 1
    endif
  endif

  # Copy diagnostic variables used in DA to bg (if needed)
  # ======================================================
  set copyDiags = 0
  foreach var ({$MPASJEDIDiagVariables})
    echo "Checking for presence of variable ($var) in ${bgFile}"
    ncdump -h ${bgFile} | grep $var
    if ( $status != 0 ) then
      @ copyDiags++
      echo "variable ($var) not present"
    endif
  end
  if ( $copyDiags > 0 ) then
    # remove link
    rm ${bgFile}

    # create copy instead
    cp -v ${bgFileOther} ${bgFile}

    # add diagnostic variables
    set diagFile = ${other}/${DIAGFilePrefix}.$fileDate.nc
    ncks -A -v ${MPASJEDIDiagVariables} ${diagFile} ${bgFile}
  endif

  # use the member-specific background as the TemplateFieldsFileOuter for this member
  rm ${TemplateFieldsFileOuter}${memSuffix}
  ln -sfv ${bgFile} ${TemplateFieldsFileOuter}${memSuffix}

  # use localStaticFieldsFileInner as the TemplateFieldsFileInner
  # NOTE: not perfect for EDA if static fields differ between members,
  #       but dual-res EDA not working yet anyway
  if ($MPASnCellsOuter != $MPASnCellsInner) then
    set tFile = ${TemplateFieldsFileInner}${memSuffix}
    rm $tFile

    #modify "Inner" initial forecast file
    # TODO: capture the naming convention for FirstCyclingFCDir somewhere else
    set memDir = `${memberDir} $DAType 1`
    set FirstCyclingFCDir = ${CyclingFCWorkDir}/${FirstCycleDate}${memDir}/Inner
    cp -v ${FirstCyclingFCDir}/${self_StatePrefix}.${nextFirstFileDate}.nc $tFile
    # modify xtime
    echo "${updateXTIME} $tFile ${thisCycleDate}"
    ${updateXTIME} $tFile ${thisCycleDate}
  endif

  foreach StreamsFile_ ($StreamsFileList)
    if (${memSuffix} != "") then
      cp ${StreamsFile_} ${StreamsFile_}${memSuffix}
    endif
    sed -i 's@TemplateFieldsMember@'${memSuffix}'@' ${StreamsFile_}${memSuffix}
    sed -i 's@analysisPrecision@'${analysisPrecision}'@' ${StreamsFile_}${memSuffix}
  end
  sed -i 's@StreamsFileMember@'${memSuffix}'@' variational_${member}.yaml

  # Remove existing analysis file, make full copy from bg file
  # ==========================================================
  set an = $CyclingDAOutDirs[$member]
  mkdir -p ${an}
  set anFile = ${an}/${ANFilePrefix}.$fileDate.nc
  rm ${anFile}
  cp -v ${bgFile} ${anFile}

  @ member++
end

echo "Completed model state preparation stage"

date

exit 0
