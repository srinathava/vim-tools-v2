pythonx import sys
pythonx import os

let s:pytoolspath = g:MW_rootDir . '/pytools'
exec 'pythonx sys.path += [r"'.s:pytoolspath.'"]'
exec 'pythonx os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'")'
exec 'pythonx os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'/selecttag")'

let s:external_apps = '//mathworks/hub/share/sbtools/external-apps'
let isInsideMW = isdirectory(s:external_apps)
if isInsideMW
    let $CTAGS_CMD = s:external_apps . '/exuberant-ctags/exuberant-ctags-5.9/exuberant-ctags/ctags'
    let g:Tlist_Ctags_Cmd = $CTAGS_CMD
endif
if isInsideMW
    if has('python')
        exec 'pythonx sys.path += [r"'.s:external_apps.'/python/python27/site-packages"]'
    elseif has('python3')
        exec 'pythonx sys.path += [r"'.s:external_apps.'/python/python3/site-packages"]'
    endif
endif
exec 'pythonx os.environ["MW_VIM_TOOLS_ROOT"] = "'.g:MW_rootDir.'"'

if has('unix')
    let $PATH = s:pytoolspath.':'.$PATH
    let $PATH = s:pytoolspath.'/selecttag:'.$PATH
else
    let $PATH = s:pytoolspath.';'.$PATH
    let $PATH = s:pytoolspath.'/selecttag;'.$PATH
endif

" mw#initpy#InitPython:  {{{
function! mw#initpy#Init()
    " Nothing to do. We just rely on the python imports above
endfunction " }}}

