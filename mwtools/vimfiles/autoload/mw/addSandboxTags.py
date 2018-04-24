import vim
from os import path
from getProjSettings import getProjSettings
from sbtools import getRootDir


def addSandboxTags(fname):
    rootDir = getRootDir()
    if not rootDir:
        return

    soln = getProjSettings()
    if not soln:
        return

    soln.setRootDir(rootDir)

    for proj in soln.projects:
        if proj.includesFile(fname):
            # add project tags
            for inc in proj.includes:
                vim.command("let &l:tags .= ',%s'" % path.join(rootDir, inc['path'], inc['tagsFile']))

            # add imported header tags.
            for dep in proj.depends:
                dep_proj = soln.getProjByName(dep)
                for inc in dep_proj.exports:
                    vim.command("let &l:tags .= ',%s'" % path.join(rootDir, inc['path'], inc['tagsFile']))


def getTagFiles(fname):
    rootDir = getRootDir()
    if not rootDir:
        return

    soln = getProjSettings()
    if not soln:
        return

    soln.setRootDir(rootDir)

    for proj in soln.projects:
        if proj.includesFile(fname):
            for inc in proj.includes:
                tagsFileFullPath = path.join(rootDir, inc['path'], inc['tagsFile'])
                return tagsFileFullPath
