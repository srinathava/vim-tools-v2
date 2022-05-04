" MW_AttachToMatlab:  {{{
" Description: 

let s:scriptDir = expand('<sfile>:p:h')
call MW_ExecPython("import sys, vim")
call MW_ExecPython("sys.path += [r'".s:scriptDir."']")
call MW_ExecPython("from startMatlab import startMatlab")

function! MW_AttachToMatlab(pid, mode)
    InitGdb

    if a:mode == '-nojvm'
        GDB handle SIGSEGV stop print
    else
        GDB handle SIGSEGV nostop noprint
    endif

    exec 'GDB attach '.a:pid

    exec 'GDB continue'
endfunction " }}}

" MW_StartMatlabWithCustomCmdLineArgs{{{
" Description:

let s:customArgs = '-nodesktop -nosplash'
function! MW_StartMatlabWithCustomCmdLineArgs(attach)
    echomsg "Provide command line arguments to start MATLAB."
    echohl WarningMsg
    echomsg "Note: Currently -r option can only take a single script name argument. Put all"
    echomsg "MATLAB commands into an M file and provide the script name as the argument to -r."
    echomsg " "
    echohl None

    let cmdLineArgs = input('Enter custom command line args: ', s:customArgs)
    if cmdLineArgs == ''
        return
    endif

    let s:customArgs = cmdLineArgs
    call MW_StartMatlab(a:attach, s:customArgs)
endfunction "}}}

" MW_StartMatlab:  {{{
" Description: 
function! MW_StartMatlab(attach, mode)
    let pid = MW_EvalPython('startMatlab("'.a:mode.'")')

    if pid == 0
        echohl Search
        echomsg 'Cannot find MATLAB process for some reason...'
        echohl None
        return
    endif

    if a:attach != 0
        call MW_AttachToMatlab(pid, a:mode)
    endif
endfunction " }}}

" MW_DebugUnitTests:  {{{
" Description: run the C++ unit tests for the current modules
function! MW_DebugUnitTests(what)
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

    InitGdb

    " The server prefix makes GDB not ask for confirmation about loading
    " symbols from the file. That confirmation request makes the next cd
    " command silently fail.
    exec 'GDB server handle SIGSEGV stop print'
    exec 'GDB server file '.testPath
    exec 'GDB server cd '.projDir
endfunction " }}}
" MW_DebugCurrentTestPoint:  {{{
" Description: 
function! MW_DebugCurrentTestPoint()
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

    call MW_DebugUnitTests('current')

    echomsg 'GDB server quick_start_unit --gtest_filter='.unitTestName
    exec 'GDB server quick_start_unit --gtest_filter='.unitTestName
endfunction " }}}

command! -nargs=* MWDebugMATLAB             :call MW_StartMatlab(1, <f-args>)
command! -nargs=1 MWDebugUnitTest           :call MW_DebugUnitTests(<f-args>)
command! -nargs=0 MWDebugCurrentTestPoint   :call MW_DebugCurrentTestPoint()

amenu &Mathworks.&Debug.&1\ MATLAB\ -nojvm          :call MW_StartMatlab(1, '-nojvm')<CR>
amenu &Mathworks.&Debug.&2\ MATLAB\ -nodesktop      :call MW_StartMatlab(1, '-nodesktop -nosplash')<CR>
amenu &Mathworks.&Debug.&3\ MATLAB\ desktop         :call MW_StartMatlab(1, '-desktop')<CR>
amenu &Mathworks.&Debug.&4\ MATLAB\ custom          :call MW_StartMatlabWithCustomCmdLineArgs(1)<CR>
amenu &Mathworks.&Debug.&Attach\ to\ MATLAB         :call MW_AttachToMatlab('MATLAB', '-nojvm')<CR>
amenu &Mathworks.&Debug.&current\ unit/pkgtest   :call MW_DebugUnitTests('current')<CR>
amenu &Mathworks.&Debug.&unittest                :call MW_DebugUnitTests('unit')<CR>
amenu &Mathworks.&Debug.&pkgtest                 :call MW_DebugUnitTests('pkg')<CR>
amenu &Mathworks.&Debug.Current\ &Test\ Point     :call MW_DebugCurrentTestPoint()<CR>

amenu &Mathworks.&Run.&1\ MATLAB\ -nojvm        :call MW_StartMatlab(0, '-nojvm')<CR>
amenu &Mathworks.&Run.&2\ MATLAB\ -nodesktop    :call MW_StartMatlab(0, '-nodesktop -nosplash')<CR>
amenu &Mathworks.&Run.&3\ MATLAB\ desktop       :call MW_StartMatlab(0, '-desktop')<CR>
amenu &Mathworks.&Run.&4\ MATLAB\ custom        :call MW_StartMatlabWithCustomCmdLineArgs(0)<CR>
amenu &Mathworks.&Run.&5\ MATLAB\ -check_malloc :call MW_StartMatlab(0, '-check_malloc')<CR>

" vim: fdm=marker
