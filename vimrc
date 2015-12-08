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
