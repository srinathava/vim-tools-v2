#!/usr/bin/env python

import xml.dom.minidom
import os
import re
from os import path
from pathUtils import searchUpFor

DEBUG = 0

def debug(msg):
    if DEBUG:
        print("DEBUG: %s" % msg)

class Solution:
    def __init__(self):
        self.projects = []
        self.rootDir = ''

    def __str__(self):
        return '\n'.join(['%s' % p for p in self.projects])

    def getProjByName(self, name):
        for proj in self.projects:
            if name == proj.name:
                return proj

        return None

    def setRootDir(self, rootDir):
        self.rootDir = rootDir
        for p in self.projects:
            p.rootDir = rootDir

class Project:
    def __init__(self, name, dllname, depends):
        self.name = name
        self.dllname = dllname
        self.includes = []
        self.exports = []
        self.depends = depends
        self.path = ''
        self.rootDir = ''

    def includesFile(self, fname):
        for inc in self.includes:
            incPath = path.abspath(path.join(self.rootDir, inc['path']))
            if incPath.lower() in path.abspath(fname).lower():
                return True

        return False

    def addInclude(self, path, pattern):
        self.includes.append({'path': path, 
                              'pattern': pattern, 
                              'tagsFile': '%s.inc.tags' % self.name,
                              'allTagsFile': '%s.all.tags' % self.name})

    def addExport(self, path, pattern):
        self.exports.append({'path': path, 'pattern': pattern, 'tagsFile': '%s.exp.tags' % self.name})

    def __str__(self):
        return ("name:%s (path:%s):"
                "\n   dllname: %s"
                "\n   includes: %s"
                "\n   exports: %s"
                "\n   depends: %s") % (self.name, self.path, self.dllname, self.includes, self.exports, ' '.join(self.depends))

def getText(doms):
    txt = ''
    for d in doms:
        for c in d.childNodes:
            if c.nodeType == c.TEXT_NODE:
                txt += c.data
    return txt

def handleProj(dom):
    name = dom.getAttribute('name')
    depends = getText(dom.getElementsByTagName('depends')).strip().split()
    moduleDLLName = ""
    proj = Project(name, moduleDLLName, depends)

    for inc_dom in dom.getElementsByTagName('include'):
        proj.addInclude(inc_dom.getAttribute('path'), inc_dom.getAttribute('pattern'))

    for exp_dom in dom.getElementsByTagName('export'):
        proj.addExport(exp_dom.getAttribute('path'), exp_dom.getAttribute('pattern'))

    return proj

def handleModuleImpl(rootDir, modPath, extraIncludes):
    depends = []

    name = path.basename(modPath)

    moduleDLLName = ""
    makeFile = path.join(rootDir, modPath, 'Makefile')
    if path.isfile(makeFile):
        modnameAssignText = re.search(r"MODNAME([\s:]*)=(.*)\n",open(makeFile).read())
        if modnameAssignText != None:
             moduleDLLName = modnameAssignText.group(2).strip()


    proj = Project(name, moduleDLLName, depends)
    proj.path = path.join(rootDir, modPath)

    incPattern = '*.[ch]pp *.c *.h'

    if extraIncludes:
        incPattern += (' %s' % extraIncludes)

    proj.addInclude(modPath, incPattern)
    proj.addExport(path.join(modPath, 'export'), '*.hpp *.h')

    derivedSrc = modPath.replace('matlab/', 'matlab/derived/glnxa64/')
    derivedInc = 'matlab/derived/glnxa64/src/include/' + name

    proj.addInclude(derivedSrc, '*.[ch]pp *.c')
    proj.addExport(derivedInc, '*.hpp *.h')
    return proj


def handleModule(dom, rootDir):
    return handleModuleImpl(rootDir, dom.getAttribute("path"),
            dom.getAttribute("extraIncludes"))

def addModuleDependencies(modules, rootDir):
    moduleNames = set()
    [moduleNames.add(mod.name) for mod in modules]
    dllNames = []
    [dllNames.append(mod.dllname) for mod in modules]
    for mod in modules:
        if not mod.path:
            continue

        dependencyFile = path.join(rootDir, mod.path, 'MODULE_DEPENDENCIES')
        if not path.isfile(dependencyFile):
            continue

        for depName in open(dependencyFile).read().splitlines():
            if depName.startswith('#'):
                continue

            if depName.startswith('='):
                depName = depName[1:]

            if depName and depName in dllNames:
                depName = modules[dllNames.index(depName)].name

            if depName in moduleNames:
                mod.depends.append(depName)
            elif depName.startswith('libmw'):
                depName = depName.replace('libmw', '', 1)
                if depName in moduleNames:
                    mod.depends.append(depName)

def handleModuleDir(soln, rootDir, moduleDir):
    moduleDirPath = path.join(rootDir, moduleDir.getAttribute("path"))
    extraIncludes = moduleDir.getAttribute("extraIncludes")

    for (dirname, _, files) in os.walk(moduleDirPath, topdown=True):
        if 'MODULE_DEPENDENCIES' in files:
            soln.projects.append(handleModuleImpl(rootDir,
                                                  path.relpath(dirname,
                                                               rootDir), extraIncludes))

def handleSolution(dom, rootDir):
    soln = Solution()

    project_doms = dom.getElementsByTagName('project')
    for proj_dom in project_doms:
        soln.projects.append(handleProj(proj_dom))

    modules = dom.getElementsByTagName('module')
    for module in modules:
        soln.projects.append(handleModule(module, rootDir))

    moduleDirs = dom.getElementsByTagName("modules_under")
    for moduleDir in moduleDirs:
        handleModuleDir(soln, rootDir, moduleDir)

    return soln

def getProjSettings():
    projSpecFile = searchUpFor('.vimproj.xml')
    mw_anchor = searchUpFor('mw_anchor')
    if mw_anchor:
        rootDir = path.dirname(mw_anchor)
    else:
        rootDir = '.'

    if not projSpecFile:
        dir_path = os.path.dirname(os.path.realpath(__file__))
        homePath = path.join(dir_path,'../plugin/.vimproj.xml')
        if path.exists(homePath):
            projSpecFile = homePath

    if projSpecFile:
        dom = xml.dom.minidom.parseString(open(projSpecFile).read())
        spec = handleSolution(dom, rootDir)
        userHomePath = path.join(os.environ['HOME'], '.vimproj.xml')
        if path.exists(userHomePath):
            dom = xml.dom.minidom.parseString(open(userHomePath).read())
            specUser = handleSolution(dom, rootDir)
            specNames = []

            for proj in spec.projects:
                specNames.append(proj.path)

            for proj in specUser.projects:
                if proj.path not in specNames:
                    # print("DEBUG: adding %s with path [%s] to project" % (proj.name, proj.path))
                    spec.projects.append(proj)

        if mw_anchor:
            addModuleDependencies(spec.projects, path.dirname(mw_anchor))

        return spec
    else:
        return None

if __name__ == "__main__":
    print(getProjSettings())
