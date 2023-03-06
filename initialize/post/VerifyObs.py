#!/usr/bin/env python3

from initialize.applications.HofX import HofX

from initialize.config.Component import Component
from initialize.config.Config import Config
from initialize.config.Resource import Resource
from initialize.config.Task import TaskLookup

from initialize.framework.HPC import HPC

from initialize.data.Model import Model, Mesh
from initialize.data.ObsEnsemble import ObsEnsemble
from initialize.data.StateEnsemble import StateEnsemble

class VerifyObs(Component):
  defaults = 'scenarios/defaults/verifyobs.yaml'
  workDir = 'Verification'
  diagnosticsDir = 'diagnostic_stats/obs'
  variablesWithDefaults = {
    'script directory': ['/glade/work/guerrett/pandac/fixed_input/graphics_ioda-conventions', str],
  }

  def __init__(self,
    config:Config,
    localConf:dict,
    hpc:HPC,
    mesh:Mesh,
    model:Model,
    states:StateEnsemble = None,
    obs:ObsEnsemble = None,
  ):
    super().__init__(config)

    base = self.__class__.__name__

    subDirectory = str(localConf['sub directory'])
    dependencies = list(localConf.get('dependencies', []))
    followon = list(localConf.get('followon', []))
    memberMultiplier = int(localConf.get('member multiplier', 1))

    ###################
    # derived variables
    ###################
    self._set('ObsDiagnosticsDir', self.diagnosticsDir) # used by compareobs.csh

    self._cshVars = list(self._vtable.keys())

    ########################
    # tasks and dependencies
    ########################
    # job settings
    attr = {
      'retry': {'typ': str},
      'seconds': {'typ': int},
      'secondsPerMember': {'typ': int},
      'nodes': {'def': 1, 'typ': int},
      'PEPerNode': {'def': 36, 'typ': int},
      'memory': {'def': '45GB', 'typ': str},
      'queue': {'def': hpc['NonCriticalQueue']},
      'account': {'def': hpc['NonCriticalAccount']},
    }
    job = Resource(self._conf, attr, ('job',))
    job['seconds'] += job['secondsPerMember'] * memberMultiplier
    task = TaskLookup[hpc.system](job)

    msg = base+': one and only one of states or obs must be defined'
    if obs is None:
      assert states is not None, msg
      self.__hofx = HofX(config, localConf, hpc, mesh, model, states)
      obsLocal = self.__hofx.outputs['obs']['members']

      appType = 'hofx'

    else:
      assert states is None, msg
      self.__hofx = None
      obsLocal = obs

      appType = 'variational'

    dt = obsLocal.duration()
    dtStr = str(dt)
    NN = len(obsLocal)

    if NN > 1:
      memFmt = '/mem{:03d}'
    else:
      memFmt = '/mean'

    self.groupName = base+subDirectory.upper()
    parentName = self.groupName
    self.groupName += '-'+dtStr+'hr'
    self.finished = self.groupName+'Finished'
    self.clean = 'Clean'+self.groupName

    # generic Post tasks and dependencies
    self._tasks += ['''
  [['''+parentName+''']]
  [['''+self.groupName+''']]
    inherit = '''+parentName+'''
'''+task.job()+task.directives()+'''
  [['''+self.finished+''']]
    inherit = '''+parentName+'''
  [['''+self.clean+''']]
    inherit = Clean''']

    self._dependencies += ['''
        '''+self.groupName+''':succeed-all => '''+self.finished]

    for d in dependencies:
      self._dependencies += ['''
        '''+d+''' => '''+self.groupName]

    for f in followon:
      self._dependencies += ['''
        '''+self.finished+''' => '''+f]

    # class-specific tasks
    for mm, o in enumerate(obsLocal):
      workDir = self.workDir+'/'+subDirectory+memFmt.format(mm+1)+'/{{thisCycleDate}}'
      if dt > 0 or 'fc' in subDirectory:
        workDir += '/'+dtStr+'hr'
      workDir += '/'+self.diagnosticsDir

      # run
      args = [
        dt,
        workDir,
        o.directory(),
        memberMultiplier,
        appType,
        #o.observers(), # incorporate obs selection into DiagnoseObsStats.py yaml/dict
      ]
      runArgs = ' '.join(['"'+str(a)+'"' for a in args])

      runName = self.groupName
      if NN > 1:
        runName += '_'+str(mm+1)
      elif memberMultiplier > 1:
        runName += '_MEAN'
      else:
        runName += '00'

      self._tasks += ['''
  [['''+runName+''']]
    inherit = '''+self.groupName+''', BATCH
    script = $origin/bin/'''+base+'''.csh '''+runArgs]

  def export(self, components):
    '''
    export for use outside python
    '''

    # add hofx tasks and dependencies when applicable
    if self.__hofx is not None:
      self._tasks += self.__hofx._tasks
      self._dependencies += self.__hofx._dependencies
      self._dependencies += ['''
        '''+self.__hofx.finished+''' => '''+self.groupName]
      self._dependencies += ['''
        '''+self.finished+''' => '''+self.__hofx.clean]
      self.__hofx.export(components)

    self._exportVarsToCsh()
    self._exportVarsToCylc()
    return
