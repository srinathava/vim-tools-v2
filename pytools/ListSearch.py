#!/usr/bin/env python3

from getProjSettings import getProjSettings
from sbtools import getRootDir
import os
from os import path
from threading import Thread
from subprocess import Popen, PIPE
import sys
from sbtools import *

class Base(Thread):
    def __init__(self, rootDir, include):
        Thread.__init__(self)

        self.rootDir = rootDir
        self.path = os.path.join(rootDir, include['path'])
        self.pattern = ' -name ' + (' -or -name '.join(include['pattern'].split()))

        exclude = '-not -name bundle.index.js -not -path *l10n* -not -path *web/release*'
        self.pattern = f'{self.path} ( {self.pattern} ) -and ( {exclude}  )'
        self.result = ''

class Lister(Base):
    def __init__(self, rootDir, include):
        super().__init__(rootDir, include)

    def run(self):
        if not os.path.exists(self.path):
            return
        self.result = getoutput(['find'] + self.pattern.split())

class Finder(Base):
    def __init__(self, rootDir, include):
        super().__init__(rootDir, include)

    def run(self):
        if not os.path.exists(self.path):
            return

        p1 = Popen(['find'] + self.pattern.split(), stdout=PIPE)
        p2 = Popen(['python', getScriptPath('findInFiles.py'), '-nH'] + sys.argv[1:], stdin=p1.stdout, stdout=PIPE)
        self.result = p2.communicate()[0]

def listOrSearchFiles(searchOnlyProj, Runner):
    rootDir = getRootDir()

    soln = getProjSettings()
    if not soln:
        raise Exception("ERROR: Project description file .vimproj.xml not found either in $HOME or the root of the sandbox.")

    soln.setRootDir(rootDir)

    # The current directory decides the "current project"
    cwd = os.getcwd()

    threads = []
    for proj in soln.projects:
        # Figure out if the current directory is in the current project
        if (not searchOnlyProj) or proj.includesFile(cwd):
            for inc in proj.includes:
                th = Runner(rootDir, inc)
                th.start()
                threads += [th]

    result = ''
    for th in threads:
        th.join()
        if len(th.result) > 5:
            result += th.result.decode('utf-8')

    return result.split("\n")
