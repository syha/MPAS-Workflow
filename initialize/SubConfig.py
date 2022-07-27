#!/usr/bin/env python3

from collections.abc import Iterable

class SubConfig():
  defaults = None
  baseKey = None
  requiredVariables = {}
  variablesWithDefaults = {}
  def __init__(self, config):
    #######################
    # renew config defaults
    #######################
    config.renew(self.defaults, self.baseKey)
    self.__config = config
    self._table = {}

    ##############
    # parse config
    ##############
    for v, t in self.requiredVariables.items():
      self.setOrDie(v, t)

    for v, a in self.variablesWithDefaults.items():
      self.setOrDefault(v, a[0], a[1])


  def initCsh(self):
    return ['''#!/bin/csh -f
######################################################
# THIS FILE IS AUTOMATICALLY GENERATED. DO NOT MODIFY.
# MODIFY THE SCENARIO YAML FILE INSTEAD.
######################################################

if ( $?config_'''+self.baseKey+''' ) exit 0
set config_'''+self.baseKey+''' = 1

''']
  def get(self, v):
    return self._table[v]

  def set(self, v, value):
    self._table[v] = value

  def setOrDie(self, v, t=None):
    self._table[v] = self.__config.getOrDie(v)
    if t is not None:
      self._table[v] = t(self._table[v])

  def setOrNone(self, v, t=None):
    self._table[v] = self.__config.get(v)
    if t is not None:
      self._table[v] = t(self._table[v])

  def setOrDefault(self, v, default, t=None):
    self._table[v] = self.__config.getOrDefault(v, default)
    if t is not None:
      self._table[v] = t(self._table[v])

  @staticmethod
  def varToCsh(var, value):
    if isinstance(value, Iterable) and not isinstance(value, str):
      vsh = str(value)
      vsh = vsh.replace('\'','')
      vsh = vsh.replace('[','')
      vsh = vsh.replace(']','')
      vsh = vsh.replace(',',' ')
      return ['set '+var+' = ('+vsh+')\n']
    else:
      return ['setenv '+var+' "'+str(value)+'"\n']

  @staticmethod
  def varToCylc(var, value):
    if isinstance(value, str):
      return ['{% set '+var+' = "'+value+'" %}\n']
    else:
      return ['{% set '+var+' = '+str(value)+' %}\n']

  @staticmethod
  def write(filename, Str):
     print('Creating '+filename)
     with open(filename, 'w') as f:
       f.writelines(Str)
       f.close()

