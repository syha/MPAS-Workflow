#!/usr/bin/env python3

from initialize.Component import Component
from initialize.Resource import Resource
from initialize.util.Task import TaskFactory

class VerifyObs(Component):
  baseKey = 'verifyobs'
  defaults = 'scenarios/defaults/verifyobs.yaml'
  variablesWithDefaults = {
    'pyVerifyDir': ['/glade/work/guerrett/pandac/fixed_input/graphics', str],
  }

  def __init__(self, config, hpc, members):
    super().__init__(config)

    ###############################
    # export for use outside python
    ###############################
    csh = list(self._vtable.keys())
    self.exportVarsToCsh(csh)

    ########################
    # tasks and dependencies
    ########################
    # job settings
    attr = {
      'retry': {'t': str},
      'seconds': {'t': int},
      'secondsPerMember': {'t': int},
      'nodes': {'def': 1, 't': int},
      'PEPerNode': {'def': 36, 't': int},
      'memory': {'def': '45GB', 't': str},
      'queue': {'def': hpc['NonCriticalQueue']},
      'account': {'def': hpc['NonCriticalAccount']},
    }
    job = Resource(self._conf, attr, 'job')
    ensSeconds = job['seconds'] + job['secondsPerMember'] * members.n
    task = TaskFactory[hpc.name](job)

    tasks = ['''
  [[VerifyObsBase]]
    inherit = BATCH
'''+task.job()+task.directives()+'''

{% if DiagnoseEnsSpreadBG %}
  {% set nEnsSpreadMem = '''+str(members.n)+''' %}
  {% set obsEnsSeconds = '''+str(ensSeconds)+''' %}
{% else %}
  {% set nEnsSpreadMem = 0 %}
  {% set obsEnsSeconds = '''+str(job['seconds'])+''' %}
{% endif %}
''']

    self.exportTasks(tasks)
