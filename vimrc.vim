syntax on
filetype plugin on

" let g:GdbCmd = 'sb -no-debug-backing-stores -debug -gdb-switches --annotate=3 -gdb-switches --args'
let $CTAGS_CMD = '/hub/share/sbtools/external-apps/exuberant-ctags/exuberant-ctags-5.9/exuberant-ctags/ctags'

let g:Tlist_Ctags_Cmd = $CTAGS_CMD

let rtp = expand('<sfile>:p:h')

set shell=bash
let pytoolspath = rtp . '/pytools'

if has('python')
    py import sys
    py import os
    exec 'py sys.path += [r"'.pytoolspath.'"]'
    exec 'py os.environ["PATH"] += (os.pathsep + "'.pytoolspath.'")'
    exec 'py os.environ["PATH"] += (os.pathsep + "'.pytoolspath.'/selecttag")'
end
if has('unix')
    let $PATH .= ':'.pytoolspath
    let $PATH .= ':'.pytoolspath.'/selecttag'
else
    let $PATH .= ';'.pytoolspath
    let $PATH .= ';'.pytoolspath.'/selecttag'
endif

exec 'set rtp+='.rtp.'/mwtools/vimfiles'
exec 'set rtp+='.rtp.'/mwtools/vimfiles/after'

if !has('unix')
    finish
endif

exec 'set rtp+='.rtp.'/gdb/vimfiles'
