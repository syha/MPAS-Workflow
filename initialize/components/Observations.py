#!/usr/bin/env python3

from initialize.Component import Component

class Observations(Component):
  defaults = 'scenarios/defaults/observations.yaml'
  workDir = 'Observations'
  InDBDir = 'dbIn'
  OutDBDir = 'dbOut'
  VarBCAnalysis = OutDBDir+'/satbias_crtm_ana'
  obsPrefix = 'obsout'
  geoPrefix = 'geoval'
  diagPrefix = 'ydiags'

  requiredVariables = {
    ## resource
    # OPTIONS: PANDACArchive, GladeRDAOnline, NCEPFTPOnline, GenerateObs (see defaults)
    'resource': str,
  }
  variablesWithDefaults = {
    ## convertToIODAObservations
    # list of raw observation types to convert to IODA format, when (resource != PANDACArchive)
    'convertToIODAObservations': [[
      'prepbufr',
      'satwnd',
      'gpsro',
      '1bamua',
      'airsev',
      #'mtiasi',
      #'1bmhs',
      #'cris',
    ], list],

    # cylc retry strings for "GetObs" and "ObsToIODA" tasks
    'getRetry': ['80*PT5M', str],
    'convertRetry': ['2*PT30S', str],

    ## GDAS observations error table
    # This file provides observation errors for all types of conventional and satwnd data
    # for 33 pressure levels (1100 hPa to 0 hPa). More information on this table can be
    # found in the GSI User's guide (https://dtcenter.ucar.edu/com-GSI/users/docs/users_guide/GSIUserGuide_v3.7.pdf)
    'GDASObsErrtable': ['/glade/work/guerrett/pandac/fixed_input/GSI_errtables/HRRRENS_errtable_10sep2018.r3dv', str],

    ## CRTM
    'CRTMTABLES': ['/glade/work/guerrett/pandac/fixed_input/crtm_bin/', str],

    # static directories for bias correction files
    'fixedCoeff': ['/glade/p/mmm/parc/ivette/pandac/SATBIAS_fixed', str],
    'fixedTlapmeanCov': ['/glade/p/mmm/parc/ivette/pandac/SATBIAS_fixed/2018', str],
    'initialVARBCcoeff': ['/glade/p/mmm/parc/ivette/pandac/SATBIAS_fixed/2018', str],
  }

  def __init__(self, config, hpc):
    super().__init__(config)

    # WorkDir is where non-IODA-formatted observation files are linked/downloaded, then converted
    self.WorkDir = self.workDir+'/{{thisValidDate}}'

    ###################
    # derived variables
    ###################
    resourceName = 'observations__resource'
    resource = self['resource']
    self._set(resourceName, resource)

    self._set('InDBDir', self.InDBDir)
    self._set('OutDBDir', self.OutDBDir)
    self._set('VarBCAnalysis', self.VarBCAnalysis)
    self._set('obsPrefix', self.obsPrefix)
    self._set('geoPrefix', self.geoPrefix)
    self._set('diagPrefix', self.diagPrefix)

    # all csh variables above
    self._cshVars = list(self._vtable.keys())

    # PrepareObservationsTasks is a list of strings
    key = 'PrepareObservationsTasks'
    values = self.extractResourceOrDie(('resources', resource), key, list)

    # first add variable as a list of tasks
    self._cylcVars.append(key)
    self._set(key, values)

    # then add as a joined string with dependencies between subtasks (" => ")
    # e.g.,
    # value: [a, b] becomes "a => b"
    key = 'PrepareObservations'
    value = " => ".join(values)
    self._cylcVars.append(key)
    self._set(key, value)
    self.workflow = key
   
    self.groupName = self.__class__.__name__
    self.Queue = hpc['CriticalQueue']
    self.Account = hpc['CriticalAccount']

  def export(self, components):
    if 'extendedforecast' in components:
      dtOffsets=components['extendedforecast']['extLengths']
    else:
      dtOffsets=[0]

    self._tasks = ['''
  [['''+self.groupName+''']]''']
    for dt in dtOffsets:
      dtStr = str(dt)
      dt_work_Args = '"'+dtStr+'" "'+self.WorkDir+'"'

      self._tasks += ['''
  [[GetObs-'''+dtStr+'''hr]]
    inherit = '''+self.groupName+''', SingleBatch
    script = $origin/applications/GetObs.csh '''+dt_work_Args+'''
    [[[job]]]
      execution time limit = PT10M
      execution retry delays = '''+self['getRetry']+'''
  [[ObsToIODA-'''+dtStr+'''hr]]
    inherit = '''+self.groupName+''', SingleBatch
    script = $origin/applications/ObsToIODA.csh '''+dt_work_Args+'''
    [[[job]]]
      execution time limit = PT600S
      execution retry delays = '''+self['convertRetry']+'''
    [[[directives]]]
      # currently ObsToIODA has to be on Cheyenne, because ioda-upgrade.x is built there
      # TODO: build ioda-upgrade.x on casper, remove Critical directives below, deferring to
      #       SingleBatch inheritance
      # Note: memory for ObsToIODA may need to be increased when hyperspectral and/or
      #       geostationary instruments are added
      -m = ae
      -q = '''+self.Queue+'''
      -A = '''+self.Account+'''
      -l = select=1:ncpus=1:mem=10GB
  [[ObsReady-'''+dtStr+'''hr]]
    inherit = '''+self.groupName]

    self._tasks += ['''
  [[GetObs]]
    inherit = GetObs-0hr
  [[ObsToIODA]]
    inherit = ObsToIODA-0hr
  [[ObsReady]]
    inherit = '''+self.groupName]

    super().export(components)
