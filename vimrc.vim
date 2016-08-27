syntax on
filetype plugin on
filetype indent on
source $VIMRUNTIME/macros/matchit.vim

set ts=8 sw=4 et bs=2 sts=4

set mousemodel=popup
set shell=bash " needed by DiffSubmitFile

com! -nargs=0 CD :exec 'cd '.expand('%:p:h')

let $CTAGS_CMD = '/hub/share/sbtools/external-apps/exuberant-ctags/exuberant-ctags-5.9/exuberant-ctags/ctags'

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
let s:pytoolspath = g:MW_rootDir . '/pytools'

if has('python')
    py import sys
    py import os
    exec 'py sys.path += [r"'.s:pytoolspath.'"]'
    exec 'py os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'")'
    exec 'py os.environ["PATH"] += (os.pathsep + "'.s:pytoolspath.'/selecttag")'
end
if has('unix')
    let $PATH .= ':'.s:pytoolspath
    let $PATH .= ':'.s:pytoolspath.'/selecttag'
else
    let $PATH .= ';'.s:pytoolspath
    let $PATH .= ';'.s:pytoolspath.'/selecttag'
endif

exec 'set rtp^='.g:MW_rootDir.'/mwtools/vimfiles'
exec 'set rtp+='.g:MW_rootDir.'/mwtools/vimfiles/after'

if has('unix')
    exec 'set rtp+='.g:MW_rootDir.'/gdb/vimfiles'
endif

