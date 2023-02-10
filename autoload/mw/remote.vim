let s:remote_machine = ''
let s:remote_sbsyscheck_ok = v:false

" mw#remote#Machine: return host name of remote machine {{{
function! mw#remote#Machine()
    return s:remote_machine
endfunction " }}}
" mw#remote#Run: run command on remote machine {{{
function! mw#remote#Run(cmd, opts={})
    return mw#term#Start(mw#remote#Wrap(cmd), a:opts)
endfunction " }}}
" mw#remote#Required: whether or not we need to connect to remote {{{
function! mw#remote#Required()
    return !empty(s:remote_machine)
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
" s:ParseSbHostLeaseOutput:  {{{
" Description: 
function! s:ParseSbHostLeaseOutput(out)
    " out is a string of the form:
    "
    " Setting -osdesc glnxa64:Debian-10 based on /mathworks/devel/sbs/37/savadhan.vim_remote_bash_21a
    " 
    "   LeaseId          Hostname               OSDesc                 Username Display ExpirationDate            HostQuiesced SbsyscheckOK
    "   -----------------------------------------------------------------------------------------------------------------------------------
    "   565446           sbd499211glnxa64       glnxa64:Debian-10      savadhan 2       2023-02-10 20:35:41 -0500     0            1            

    let lines = split(trim(a:out), '\n')
    let lastline = lines[-1]
    let tokens = split(lastline)

    let machineName = tokens[1]
    let sbsysCheckStatus = tokens[-1] == '1'
    return [machineName, sbsysCheckStatus]
endfunction " }}}
" s:LeaseMachine: lease machine {{{
" Description: 
function! s:LeaseMachine(projdir)
    let out = system('sbhostlease -s '.a:projdir.' -list')
    if out =~ 'No active leases'
        echomsg "No active leases. Leasing a new machine compatiable with the current sandbox."
        let out = system('sbhostlease -s '.a:projdir.' -no-launch')
        echomsg "Checking status of newly leased machine"
        let out = system('sbhostlease -s '.a:projdir.' -list')
    endif
    let [machineName, s:remote_sbsyscheck_ok] = s:ParseSbHostLeaseOutput(out)
    return machineName
endfunction " }}}
" s:ChooseRemoteMachine: choose remote machine name {{{
" Description: 
function! s:ChooseRemoteMachine(machineName)
    if !empty(a:machineName)
        return a:machineName
    endif

    let projdir = mw#utils#GetRootDir()
    let usesbhostlease = v:false
    if filereadable(projdir.'/mw_anchor')
        let prompt = "Enter name of remote machine (or leave blank to sbhostlease for the current sandbox): "
        let usesbhostlease = v:true
    else
        let prompt = "Enter name of remote machine: "
    endif

    let ans = input(prompt)
    if empty(ans) && usesbhostlease
        return s:LeaseMachine(projdir)
    endif
    return ans
endfunction " }}}
" mw#remote#SetRemote: sets remote machine {{{
" Description: 
function! mw#remote#SetRemote(machineName='')
    let s:remote_machine = s:ChooseRemoteMachine(a:machineName)
    if empty(&titlestring)
        set titlestring=%{mw#remote#GetTitleString()}
    endif
    echomsg "Setting ".s:remote_machine." as target for GDB and compile commands"
endfunction " }}}
" mw#remote#GetTitleString {{{
function! mw#remote#GetTitleString()
    "titlestring format: filenameWithoutDirectoryPath [-+=] dirNameRelativeToSbroot : sbsName : hostNameIfRemote
    let modifierstatus = ''
    if &modifiable == 0
        let modifierstatus = '-'
    elseif &readonly == 1 && empty(getbufinfo('%')) == 0 && getbufinfo('%')[0].changed == 1
        let modifierstatus = '=+'
    elseif &readonly == 1
        let modifierstatus = '='
    elseif empty(getbufinfo('%')) == 0 && getbufinfo('%')[0].changed == 1
        let modifierstatus = '+'
    endif

    if !empty(modifierstatus)
        let modifierstatus = '['.modifierstatus.']'
    endif
    let mw_anchor_loc = findfile('mw_anchor', '.;')
    let fileName = expand('%:t')
    let dirName = expand('%:p:h')
    if mw_anchor_loc != ''
        let sbrootDir = mw#utils#GetRootDir().'/'
        let sbsName = split(sbrootDir,'/')[-1]
        let dirNameRelativeToSbroot = substitute(dirName,sbrootDir,'','g')
	let machineInfo = mw#remote#Machine()
        if !empty(machineInfo)
            let machineInfo = ' : '. machineInfo
        endif
        return fileName.' '.modifierstatus.' : '.dirNameRelativeToSbroot.' : '.sbsName.machineInfo
    else
        return fileName.' '.modifierstatus.' ('.dirName.')'
    endif
endfunction " }}}
