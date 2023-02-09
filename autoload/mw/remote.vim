let s:mw_version = ''
let s:remote_machine = ''

" mw#remote#Machine: return host name of remote machine {{{
function! mw#remote#Machine()
    call mw#remote#Required()
    return s:remote_machine
endfunction " }}}
" mw#remote#Run: run command on remote machine {{{
function! mw#remote#Run(cmd, opts={})
    return mw#term#Start(mw#remote#Wrap(cmd), a:opts)
endfunction " }}}
" mw#remote#Required: whether or not we need to connect to remote {{{
function! mw#remote#Required()
    if $RUNONSERVER != 1
        return 0
    endif
    if empty(s:mw_version) 
        let mw_anchor_loc = findfile('mw_anchor', '.;')
        let s:mw_version = split(readfile(mw_anchor_loc,'b')[0],'=')[1]
        let s:remote_machine = trim(system('getserverinfo'))
    endif
    return 1 
endfunction " }}}
" s:GetServerCmd: wrap the passed in command so it is executable remotely {{{
" Description: 
function! mw#remote#Wrap(cmd)
    let cmd = 'cd '.getcwd().'; '.a:cmd
    return ['ssh',
                \ '-t',
                \ '-Y',
                \ '-oStrictHostKeyChecking=no',
                \ s:remote_machine,
                \ cmd
                \ ]
endfunction " }}}
