" mw#gdb#AttachToMATLAB:  {{{
" Description: 

let s:scriptDir = expand('<sfile>:p:h')

function! mw#gdb#AttachToMATLAB(pid, mode)
    if a:mode == '-nojvm'
        let segvHandler = 'GDB handle SIGSEGV stop print'
    else
        let segvHandler = 'GDB handle SIGSEGV nostop noprint'
    endif
    let s:on_gdb_started = [
                \ segvHandler,
                \ 'GDB attach '.a:pid,
                \ 'GDB continue',
                \ ]

    augroup TermdebugWrapperAttach
        au!
        au User TermDebugStarted call s:IssuePendingCommands()
    augroup END

    Termdebug
endfunction " }}}
" mw#gdb#StartMATLABWithCustomCmdLineArgs{{{
" Description:

let s:customArgs = '-nodesktop -nosplash'
function! mw#gdb#StartMATLABWithCustomCmdLineArgs(attach)
    let cmdLineArgs = input('Enter custom command line args: ', s:customArgs)
    if cmdLineArgs == ''
        return
    endif

    let s:customArgs = cmdLineArgs
    call mw#gdb#StartMATLAB(a:attach, s:customArgs)
endfunction "}}}
" mw#gdb#StartMATLAB:  {{{
" Description: 
let s:python_path_inited = 0

function! mw#gdb#StartMATLAB(attach, mode)

    pythonx import sys, vim
    if s:python_path_inited == 0
        exec "pythonx sys.path += [r'".s:scriptDir."']"
        pythonx from startMatlab import startMatlab
        let s:python_path_inited = 1
    endif

    let pid = pyxeval('startMatlab(r""" '.a:mode.' """)')

    if RequiresRemote()
        echomsg "starting remote MATLAB; Use feature('getpid') in MATLAB to get pid to attach"
        return
    end
    if pid == 0
        echohl Search
        echomsg 'Cannot find MATLAB process for some reason...'
        echohl None
        return
    endif
    let @m = pid
    echomsg "Started MATLAB. Copied pid [".pid."] to register m. Use <C-r>m to use it"

    if a:attach != 0
        call mw#gdb#AttachToMATLAB(pid, a:mode)
    endif
endfunction " }}}
" s:IssuePendingCommands: issues pending GDB commands {{{
" Description: 
function! s:IssuePendingCommands()
    for cmd in s:on_gdb_started
        exec cmd
    endfor
endfunction " }}}
" mw#gdb#UnitTests:  {{{
" Description: run the C++ unit tests for the current modules
function! mw#gdb#UnitTests(what)
    let projDir = mw#sbtools#GetCurrentProjDir()
    if projDir == ''
        echohl Error
        echomsg "Could not find a project directory for current file"
        echohl None
        return
    end

    if a:what == 'current'
        let fileDirRelPathToProj = strpart(expand('%:p:h'), len(projDir) + 1)
        let testName = substitute(fileDirRelPathToProj, '/', '_', 'g')
    elseif a:what == 'unit'
        let testName = '*unittest'
    elseif a:what == 'pkg'
        let testName = '*pkgtest'
    endif

    let sbrootDir = mw#utils#GetRootDir()

    " This is the directory where 'mw_anchor' is found
    let mlroot = sbrootDir.'/matlab'

    let projRelPathToMlRoot = strpart(projDir, len(mlroot) + 1)

    let testBinDir = mlroot.'/derived/glnxa64/testbin/'.projRelPathToMlRoot
    let testPath = testBinDir.'/'.testName

    let testFiles = split(glob(testPath))
    if len(testFiles) > 1
        let choices = ['Multiple '.a:what.' tests found. Please select one: ']
        for idx in range(len(testFiles))
            call add(choices, (idx+1).'. '.fnamemodify(testFiles[idx], ':t'))
        endfor
        let choice = inputlist(choices)
        if choice <= 0
            return
        endif
        let testPath = testFiles[choice-1]
    elseif len(testFiles) == 1
        let testPath = testFiles[0]
    else
        let testPath = ''
    end

    if !executable(testPath)
        echohl Error
        echomsg "Current file is not a unit/pkg test or the unit/pkg tests have not been built"
        echohl None
        return
    end

    " The server prefix makes GDB not ask for confirmation about loading
    " symbols from the file. That confirmation request makes the next cd
    " command silently fail.
    let s:on_gdb_started = [
                \ 'GDB server handle SIGSEGV stop print',
                \ 'GDB server file '.testPath,
                \ 'GDB server cd '.projDir,
                \ ]

    augroup TermdebugWrapperAttach
        au!
        au User TermDebugStarted call s:IssuePendingCommands()
    augroup END

    Termdebug
endfunction " }}}
" mw#gdb#CurrentTestPoint:  {{{
" Description: 
function! mw#gdb#CurrentTestPoint()
    let pattern = '^\s*\w*TEST\s*(\s*\(\w\+\)\s*,\s*\(\w\+\)'
    let [lnum, colnum] = searchpos(pattern, 'bn')
    if lnum == 0
        echohl Error
        echomsg "No unit test found"
        echohl None
        return
    endif

    let txt = getline(lnum)
    let matches = matchlist(txt, pattern)
    let unitTestName = matches[1].'.'.matches[2]

    call mw#gdb#UnitTests('current')
    let s:on_gdb_started += ['GDB server quick_start_unit --gtest_filter='.unitTestName]
endfunction " }}}


" vim: fdm=marker
