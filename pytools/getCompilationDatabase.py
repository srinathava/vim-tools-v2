#!/usr/bin/env python3

import sys
from os import path
import os
import xml.etree.cElementTree as ET
import subprocess
import sbtools
from pathUtils import searchUpFor
import json

def getMatlabRoot():
    return path.join(sbtools.getRootDir(), 'matlab')

def getModuleRoot():
    moduleDepsPath = searchUpFor('MODULE_DEPENDENCIES')
    return path.dirname(moduleDepsPath)

def normalizePath(dirName, relPath):
    return os.path.abspath(os.path.join(dirName, relPath))

def getFlags(filename):
    absfilename = path.abspath(filename)
    os.chdir(path.dirname(absfilename))

    moduleRoot = getModuleRoot()
    os.chdir(moduleRoot)

    filename = path.relpath(absfilename, moduleRoot)

    mlroot = getMatlabRoot()

    relModulePath = path.relpath(moduleRoot, mlroot)

    moduleDataFile = path.join(mlroot, 'derived', 'glnxa64', 'modules', relModulePath, 'module_data.xml')

    root = ET.fromstring(open(moduleDataFile).read())

    flags = []
    flags.extend([f.text for f in root.findall('./CPPFLAGS/flag')])
    flags.extend([f.text for f in root.findall('./CXXFLAGS/flag')])
    flags.extend([('-I%s' % normalizePath(moduleRoot, inc.text)) for inc in root.findall('./moduleIncludePath/dir')])
    flags.extend(['-Wno-unused-parameter'])

    return (flags, moduleRoot)

def getCompilationDatabase(filename):
    (flags, moduleRoot) = getFlags(filename)

    flagstr = ' '.join(flags)
    cmdline = 'clang++ %(flagstr)s -c %(filename)s -o /tmp/foo.o' % locals()

    obj = {}
    obj['directory'] = moduleRoot
    obj['file'] = filename
    obj['command'] = cmdline

    objlist = [obj]
    jsonstr = json.dumps(objlist, indent=2)
    return jsonstr

if __name__ == "__main__":
    print((getCompilationDatabase(sys.argv[1])))


