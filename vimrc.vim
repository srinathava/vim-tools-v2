syntax on
filetype plugin on
filetype indent on
source $VIMRUNTIME/macros/matchit.vim

set ts=8 sw=4 et bs=2 sts=4

set mousemodel=popup
set shell=bash " needed by DiffSubmitFile

com! -nargs=0 CD :exec 'cd '.expand('%:p:h')

let s:external_apps = '//mathworks/hub/share/sbtools/external-apps'
let $CTAGS_CMD = s:external_apps . '/exuberant-ctags/exuberant-ctags-5.9/exuberant-ctags/ctags'

let g:GdbCmd = 'sb -no-debug-backing-stores -debug -gdb-switches --annotate=3 -gdb-switches --args'

let g:Tlist_Ctags_Cmd = $CTAGS_CMD

map <F3> <Plug>StartBufExplorer
map <S-F3> <Plug>SplitBufExplorer

set diffexpr=MyDiff()
function! MyDiff()
    let opt = ""
    if &diffopt =~ "icase"
        let opt = opt . "-i "
    endif
    if &diffopt =~ "iwhite"
        let opt = opt . "-w "
    endif
    silent execute "!diff -a --binary " . opt . v:fname_in . " " . v:fname_new .
        \  " > " . v:fname_out
endfunction

let g:MW_rootDir = expand('<sfile>:p:h')
let g:MW_sbtoolsDir = fnamemodify(g:MW_rootDir, ':h:h')

let s:pytoolspath = g:MW_rootDir . '/pytools'
" MW_ExecPython: executes a command in either of python or python3
" Description: 
function! MW_ExecPython(cmd)
    if has('pythonx')
        exec 'pythonx '.a:cmd
    elseif has('python')
        exec 'python '.a:cmd
    else
        exec 'python3 '.a:cmd
    endif
endfunction

function! MW_EvalPython(cmd)
    if has('pythonx')
        return pyxeval(a:cmd)
    elseif has('python')
        return pyeval(a:cmd)
    else
        return py3eval(a:cmd)
    endif
endfunction

call MW_ExecPython('import sys')
call MW_ExecPython('import os')
call MW_ExecPython('sys.path += [r"'.s:pytoolspath.'"]')
call MW_ExecPython('os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'")')
call MW_ExecPython('os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'/selecttag")')
if has('python')
    call MW_ExecPython('sys.path += [r"'.s:external_apps.'/python/python27/site-packages"]')
elseif has('python3')
    call MW_ExecPython('sys.path += [r"'.s:external_apps.'/python/python3/site-packages"]')
endif

if has('unix')
    let $PATH = s:pytoolspath.':'.$PATH
    let $PATH = s:pytoolspath.'/selecttag:'.$PATH
else
    let $PATH = s:pytoolspath.';'.$PATH
    let $PATH = s:pytoolspath.'/selecttag;'.$PATH
endif

exec 'set rtp^='.g:MW_rootDir.'/mwtools/vimfiles'
exec 'set rtp+='.g:MW_rootDir.'/mwtools/vimfiles/after'

if has('unix')
    exec 'set rtp+='.g:MW_rootDir.'/gdb/vimfiles'
endif
