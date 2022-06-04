" ==============================================================================
" Sandbox commands
" ============================================================================== 
let s:scriptPath = expand('<sfile>:p:h')

if !exists('*PrintDebug')
function! PrintDebug(...)
endfunction
endif

command! -nargs=1 ReturnWithError 
    \ echohl ErrorMsg |
    \ echomsg <args> |
    \ echohl None |
    \ return

" mw#sbtools#DiffWithOther: diffs with file in another sandbox {{{
function! mw#sbtools#DiffWithOther(otherDir)
    let otherDir = mw#utils#NormalizeSandbox(a:otherDir)
    let otherFileName = mw#utils#GetOtherFileName(otherDir)
    if otherFileName == ''
        ReturnWithError "No equivalent file found in other sandbox"
    endif

    " make this the only window.
    wincmd o
    if winnr('$') != 1
        ReturnWithError 'Could not close all other open windows'
    endif

    call mw#utils#SaveSettings(['diff', 'foldcolumn', 'foldenable', 'scrollbind', 'wrap'])
	exec 'rightb vert diffsplit '.otherFileName
    nmap <buffer> q :q<CR>:call mw#utils#RestoreSettings()<CR>
endfunction " }}}
" mw#sbtools#SplitWithOther: opens equivalent file in other sandbox {{{
function! mw#sbtools#SplitWithOther(otherDir)
    let otherDir = mw#utils#NormalizeSandbox(a:otherDir)
    let otherFileName = mw#utils#GetOtherFileName(otherDir)
    call mw#utils#AssertError(otherFileName != '',  'No equivalent file found in other sandbox')
    exec 'rightb vert split '.otherFileName
endfunction " }}}
" mw#sbtools#DiffWriteable2: diffs all writeable files {{{
" Description: diffs all writeable files in the present sandbox with the
" corresponding files in the other sandbox
function! mw#sbtools#DiffWriteable2(sb1, sb2)
    let g:DirDiffCmd = 'diffwriteable'
    let g:DirDiffCmdOpts = ''

    call PrintDebug('DirDiff '.a:sb1.' '.a:sb2, 'sbtools')
    exec 'DirDiff '.a:sb1.' '.a:sb2
    1 wincmd w
endfunction " }}}
" mw#sbtools#DiffWriteable1: diffs all writeable files {{{
" Description: diffs all writeable files in the present sandbox with the
" corresponding files in the other sandbox
function! mw#sbtools#DiffWriteable1(sb2)
    let sb1 = mw#utils#GetRootDir()
    call mw#utils#AssertError(sb1 != '', 'The present file doesn''t lie in a sandbox.')

    let sb2 = mw#utils#NormalizeSandbox(a:sb2)
    call mw#sbtools#DiffWriteable2(sb1, sb2)
endfunction " }}}
" mw#sbtools#DiffSubmitFile: diffs files in submit file {{{
" Description: 
function! mw#sbtools#DiffSubmitFile(sb1, ...)
    let sb2 = mw#utils#GetRootDir()
    if sb2 == ''
        ReturnWithError "The present file does not belong to a sandbox"
    endif

    let sb1 = mw#utils#NormalizeSandbox(a:sb1)
    if sb1 == ''
        ReturnWithError "Cannot find sandbox ".a:sb1
    end

    if a:0 > 0
        let submitFile = a:1
    else
        if !filereadable(sb2.'/submitList')
            ReturnWithError "Did not find a file called submitList at the root of the current sandbox ".sb2
        endif
        let submitFile = matchstr(readfile(sb2.'/submitList'), '\S\+')
    endif
    let submitFile = resolve(fnamemodify(submitFile, ':p'))
    if !filereadable(submitFile)
        ReturnWithError "File ".submitFile." is not readable."
    endif

    let g:DirDiffCmd = 'diffsubmitfile.py'
    let g:DirDiffCmdOpts = '-f '.submitFile

    call PrintDebug('DirDiff '.sb2.' '.sb1, 'sbtools')
    exec 'DirDiff '.sb2.' '.sb1
    1 wincmd w
endfunction " }}}
" mw#sbtools#SaveSession:  {{{
" Description: 

let s:sessionFileName = ''
function! mw#sbtools#SaveSession()
    if s:sessionFileName == ''
        let s:sessionFileName = mw#utils#GetRootDir().'/session.vim'
    endif

    let origSessOpts = &sessionoptions
    let &sessionoptions = 'buffers,globals,winpos,winsize,curdir,resize'
    exec 'mksession! '.s:sessionFileName
    let &sessionoptions = origSessOpts
endfunction " }}}
" mw#sbtools#LoadSession:  {{{
" Description: 
function! mw#sbtools#LoadSession()
    let s:sessionFileName = mw#utils#GetRootDir().'/session.vim'
    exec 'source '.s:sessionFileName
    redraw!

    augroup SaveSessionOnLeave
        au VimLeavePre * call mw#sbtools#SaveSession()
    augroup END
endfunction " }}}

" ==============================================================================
" Finding in project/solution
" ============================================================================== 
" mw#sbtools#FindIn:  {{{
" Description: 
function! mw#sbtools#FindIn(prog, dir, name, str)
    let rootDir = mw#utils#GetRootDir()

    if empty(rootDir)
        echohl Error
        echomsg "Not in a sandbox directory or a git repo"
        echohl None
        return
    endif

    if filereadable(rootDir . '/mw_anchor')
        let prog = a:prog
        let startdir = a:dir
    else
        if executable('rg')
            let prog = 'rg --vimgrep'
        else
            let prog = 'grep --exclude-dir=.git -r'
            if filereadable(rootDir.'/.gitignore')
                let prog .= ' --exclude-from='.rootDir.'/.gitignore'
            endif
        endif
        let startdir = rootDir
    endif

    let searchstr = a:str
    if searchstr == ''
        let searchstr = input('Enter grep options and pattern ('.a:name.'): ', expand('<cword>'))
        if searchstr == ''
            return
        endif
    endif

    let origDir = getcwd()
    let orig_grepprg = &grepprg

    exec 'cd '.startdir
    let &grepprg = prog.' $*'
    exec 'silent! grep '.searchstr

    let &grepprg = orig_grepprg
    exec 'cd '.origDir

    cwindow
endfunction " }}}
" mw#sbtools#FindInProj: finds pattern in project {{{
function! mw#sbtools#FindInProj(...)
    let str = a:0 > 0 ? a:1 : ''
    call mw#sbtools#FindIn('findInProj.py', expand('%:p:h'), 'grep project', str)
endfunction " }}}
" mw#sbtools#FindInSolution: finds pattern in project {{{
function! mw#sbtools#FindInSolution(...)
    let str = a:0 > 0 ? a:1 : ''
    call mw#sbtools#FindIn('findInSoln.py', expand('%:p:h'), 'grep solution', str)
endfunction " }}}
" mw#sbtools#FindUsingSbid: find using sbglobal {{{
" Description: 
function! mw#sbtools#FindUsingSbid()
    call mw#sbtools#FindIn('sbid gid -id-lang C,C++', mw#utils#GetRootDir(), 'sbid')
endfunction " }}}
" mw#sbtools#FindUsingSbglobal: find using sbglobal {{{
" Description: 
function! mw#sbtools#FindUsingSbglobal()
    call mw#sbtools#FindIn('sbglobal -grep-format -x', mw#utils#GetRootDir(), 'sbglobal')
endfunction " }}}
" mw#sbtools#FindUsingSourceCodeSearch: find using source code search {{{
" Description: 
function! mw#sbtools#FindUsingSourceCodeSearch()
    call mw#sbtools#FindIn('findUsingSCSTool.py', mw#utils#GetRootDir(), 'source code search')
endfunction " }}}

" ==============================================================================
" Editing files fast
" ============================================================================== 
let g:EditFileComplete_Debug = ''
let s:lastArg = ''
" mw#sbtools#EditFileCompleteFunc {{{
function! mw#sbtools#EditFileCompleteFunc(A,L,P)
    " let g:EditFileComplete_Debug .= "called with '".a:A."', lastArg = '".s:lastArg."'\n"

    let alreadyFiltered = 0
    if s:lastArg != '' && a:A =~ '^'.s:lastArg
        let files = s:lastFiles
        let alreadyFiltered = 1
    else
        let g:EditFileComplete_Debug .= "doing sblocate\n"
        let files = split(system('sblocate '.a:A), "\n")
    end
    " let g:EditFileComplete_Debug .= "files = ".join(files, "\n")."\n"

    if alreadyFiltered == 0
        call filter(files, 'v:val !~ "CVS"')
        call filter(files, 'v:val =~ "\\(cpp\\|hpp\\|\\|c\\|h\\|m\\|cdr\\)$"')
        " call filter(files, 'v:val =~ "matlab/\\(src/\\(cg_ir\\|rtwcg\\|simulink\\)\\|toolbox/stateflow\\|test/tools/sfeml\\)"')
        call filter(files, 'v:val =~ "/'.a:A.'[^/]*$"')
        call map(files, 'matchstr(v:val, "'.a:A.'[^/]*$")') 
    else
        call filter(files, 'v:val =~ "^'.a:A.'"')
    endif

    let s:lastArg = a:A
    let s:lastFiles = files
    return files
endfun
" }}}
" mw#sbtools#EditFileUsingLocate {{{
function! mw#sbtools#EditFileUsingLocate(file)
    let files = split(system('sblocate '.a:file), "\n")
    if len(files) == 1
        exec 'drop '.files[0]
        return
    end
    let promptList = ['Multiple files found. Please select one: ']
    for idx in range(len(files))
        call add(promptList, idx.'. '.files[idx])
    endfor
    let choice = inputlist(promptList)
    if choice < 0
        return
    endif
    exec 'drop '.files[choice]
endfun
" }}}

" ==============================================================================
" Terminal compatibility layer
" ============================================================================== 

" ==============================================================================
" Compiling projects
" ============================================================================== 
" mw#sbtools#SetCompileLevelForProject:  {{{
" Description: 

if !exists('g:MWProjectCompileLevel')
    let g:MWProjectCompileLevel = 1
endif

if !exists('g:MWCustomCompile')
    let g:MWCustomCompile = 'sbmake -distcc DEBUG=1 NOBUILDTESTS=1 NORUNTESTS=1'
endif

function! mw#sbtools#SetCompileLevelForProject()
    " User selects configuration when building a project 
    let g:MWProjectCompileLevel = inputlist(['Select compiler level for compiling project:', 
        \ '1. Build source only',
        \ '2. Build source and test',
        \ '3. Build and run tests',
        \ '4. Build for coverage',
        \ '5. Custom compile (specified using g:MWCustomCompile)'])

    " Now if we get a custom compile line, lets verify that its OK.
    if g:MWProjectCompileLevel == 5
        let g:MWCustomCompile = input('Edit current compiler invokation: ', g:MWCustomCompile)
    endif
endfunction " }}}
" mw#sbtools#SetCompileLevelForFile:  {{{
" Description: 

if !exists('g:MWFileCompileLevel')
    let g:MWFileCompileLevel = 1
endif

function! mw#sbtools#SetCompileLevelForFile()
    " User selects configuration when building a single file
     let g:MWFileCompileLevel = inputlist(['Select compiler level for compiling a single file:', 
        \ '1. Mixed compile (sbcc -cc MIXED@DEFAULT)',
        \ '2. Debug compile (sbcc -dc)',
        \ '3. Release compile (sbcc -rc)',
        \ '4. Multi-compile (sbcc -standard)',
        \ '5. Polyspace bug finder (sbcc -polyspace RELEASE)',
        \ '6. Lint only mode (sbcc -lint RELEASE)', 
        \ '7. Minimize includes (not yet supported)'])
endfunction " }}}
" s:GetProjectMakePrg: sets the 'makeprg' option for the current buffer {{{
let g:MWDebug = 1
function! s:GetProjectMakeProgram()
    let cdPath = s:GetModulePath()

    if g:MWProjectCompileLevel == 1
        "1. Build source only"
        return 'sbmake -C '.  cdPath .  '  -distcc NOBUILDTESTS=1 NORUNTESTS=1 DEBUG=1'
    elseif g:MWProjectCompileLevel == 2
        "2. Build source and test"
        return 'sbmake  -C '.  cdPath .  ' -distcc NORUNTESTS=1 DEBUG=1'
    elseif g:MWProjectCompileLevel == 3
        "3. Build and run tests"
        return 'sbmake  -C '.  cdPath .  ' -distcc DEBUG=1'
    elseif g:MWProjectCompileLevel == 4
        "4. Build for coverage"
        return 'sbmake -C '.  cdPath .  '  BCOV=1 -j 9 DEBUG=1'
    elseif g:MWProjectCompileLevel == 5
        "5. Custom compile (specified using g:MWCustomCompile)'])
        return g:MWCustomCompile
    else
        return 'sbmake -distcc' "ERROR?"
    endif
endfunction " }}}
" s:GetModulePath: gets the MathWorks module for the current file {{{
function! s:GetModulePath()
    let filePath = expand('%:p:h')

    let modDepFilePath = findfile('MODULE_DEPENDENCIES', filePath.';')
    if modDepFilePath != ''
        return fnamemodify(modDepFilePath, ':p:h')
    elseif filePath =~ 'matlab/toolbox/stateflow/src'
        return matchstr(filePath, '^.*toolbox/stateflow/src')
    elseif filePath =~ 'matlab/src'
        return matchstr(filePath, '^.*matlab/src/\w\+')
    else
        echohl ErrorMsg
        echomsg "Do not know how to handle current file"
        echohl None
        return
    end
endfunction " }}}
" s:GetFileMakePrg: sets the 'makeprg' option for the current buffer {{{
function! s:GetFileMakeProgram(fileToBuild)
    if g:MWFileCompileLevel == 1
        "1. Mixed compile (sbcc -cc MIXED@DEFAULT)"
        return 'sbcc -cc MIXED@DEFAULT ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 2
        "2. Debug compile (sbcc -dc)"
        return 'sbcc -dc ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 3
        "3. Release compile (sbcc -rc)"
        return 'sbcc -rc ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 4
        "4. Multi-compile (sbcc -standard)"
        return 'sbcc -standard ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 5
        "5. Polyspace bug finder (sbcc -polyspace RELEASE)"
        return 'sbcc -polyspace RELEASE ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 6
        "6. Lint only mode (sbcc -lint RELEASE)"
        return 'sbcc -lint RELEASE ' . a:fileToBuild
    elseif g:MWFileCompileLevel == 7
        "7. Minimize includes (not yet supported)"
        return 'sbmininclude ' . a:fileToBuild
    endif
endfunction " }}}
" mw#sbtools#GetCurrentProjDir {{{
function! mw#sbtools#GetCurrentProjDir()
    let olddir = getcwd()
    let filePath = expand('%:p:h')

    let modDepFilePath = findfile('MODULE_DEPENDENCIES', filePath.';')
    let projDir = fnamemodify(modDepFilePath, ':p:h')
    return projDir
endfunction
" }}}
" s:HandleBuildResults:  {{{
" Description: 
function! s:HandleBuildResults(status)
    if !has('nvim')
        let &termwinsize = s:old_termwinsize
    endif

    if a:status == 0
        return
    endif

    let curpos = getcurpos()
    let curbuf = bufnr('%')

    exec 'cgetbuffer '.s:term_buf
    cwindow

    exec 'bdelete '.s:term_buf
    silent! crewind
    silent! cnext

    if s:term_buf != curbuf
        exec bufwinnr(curbuf).' wincmd w'
        call setpos('.', curpos)
    endif

    redraw!
endfunction " }}}
" s:ParseBuildResults: {{{
function s:ParseBuildResults(job, status, ...)
    call timer_start(500, {timer -> s:HandleBuildResults(a:status)})
endfunction " }}}
" s:AppendBufLine: {{{
function! s:AppendBufLine(bufnum, lines)
    " Remove all ANSI escape codes
    let lines = map(a:lines, {_, s -> substitute(s, '\(\%x1b\[[0-9;]*[mGKHF]\)\|\(\)', '', 'g')})

    let lnum = getbufinfo(a:bufnum)[0]['linecount']
    call appendbufline(a:bufnum, lnum, lines)

    let lnum = getbufinfo(a:bufnum)[0]['linecount']
    let winid = bufwinid(a:bufnum)
    call nvim_win_set_cursor(winid, [lnum, 0])
endfunction
" }}}
" s:Nvim_OnOutput: handle nvim job output {{{
function! s:Nvim_OnOutput(chanId, data, name)
    if a:data[0] == ''
        return
    endif

    let a:data[0] = s:nvim_partial_data . a:data[0]
    let lines = a:data[0:-2]
    let s:nvim_partial_data = a:data[-1]

    call s:AppendBufLine(s:term_buf, lines)
endfunction " }}}
" s:Nvim_OnExit: {{{
function! s:Nvim_OnExit(jobId, exitCode, eventType)
    call s:AppendBufLine(s:term_buf, [s:nvim_partial_data])
    if a:exitCode == 0
        call s:AppendBufLine(s:term_buf, ["*** Build passed! ***"])
    else
        call s:AppendBufLine(s:term_buf, ["*** Build failed! ***"])
    endif

    call s:HandleBuildResults(a:exitCode)
endfunction " }}}
" s:CompileCommon:  {{{
" Description: 
let s:term_buf = -1
function! s:CompileCommon(makeprg)
    let cdPath = s:GetModulePath()
    cclose
    exec 'silent! bdelete '.s:term_buf

    if !has('nvim')
        let s:old_termwinsize = &termwinsize
        let &termwinsize = '10*1000'

        bot let s:term_buf = term_start(a:makeprg, {
                    \ "cwd": cdPath, 
                    \ "term_name": "sbmake term",
                    \ "exit_cb": function('s:ParseBuildResults')})
    else
        bot new
        resize 10
        setlocal buftype=nofile
        setlocal nowrap
        let s:term_buf = bufnr('%')

        let s:nvim_partial_data = ''
        let s:nvim_jobid = jobstart(a:makeprg, {
            \ 'on_stdout': function('s:Nvim_OnOutput'),
            \ 'on_exit': function('s:Nvim_OnExit'),
            \ 'pty': v:true,
            \ })
    endif
endfunction " }}}
" mw#sbtools#CompileProject: compiles the present flag {{{
let s:term_job = {}
function! mw#sbtools#CompileProject()
    call s:CompileCommon(s:GetProjectMakeProgram())
    if expand('%:p') != ''
        exec 'silent! !genVimTags.py '.expand('%:p').' &'
    endif
endfunction 
" }}}
" mw#sbtools#CompileFile: compiles present file {{{
" Description: 
function! mw#sbtools#CompileFile()
    call s:CompileCommon(s:GetFileMakeProgram(expand('%:p')))
endfunction 
" }}}
" mw#sbtools#BuildUsingDas:  {{{
function! mw#sbtools#BuildUsingDas()
    let logFile = '/tmp/_DAS_OUTPUT_'.$USER
    exec 'silent! bdelete! '.logFile
    exec 'bot spl '.logFile
    %d_
    set nomodified

    redraw!
    let cmd = input('Enter das command: ', 'das build -t cg_ir -i 0')
    let output = system(cmd)
    0put=output

    if search(': error:') == 0
        q!
        return
    endif

    nmap <buffer> <CR> :call mw#sbtools#TakeMeThere()<CR>

    w
endfunction " }}}
" mw#sbtools#TakeMeThere {{{
function! mw#sbtools#TakeMeThere()
    let matches = matchlist(getline('.'), '\(\f\+\):\(\d\+\).*')
    if len(matches) == 0
        return
    endif
    let fname = matches[1]
    let lnum = matches[2]
    let fullfilename = system('sblocate '.fname)
    exec 'split '.fullfilename
    exec lnum
endfunction
" }}}

" vim: fdm=marker
