" ==============================================================================
" Perforce commands
" ============================================================================== 

let s:scriptDir = expand('<sfile>:p:h')
function! s:InitScript()
    pythonx import sys
    pythonx import vim
    exec 'pythonx sys.path += [r"'.s:scriptDir.'"]'
    pythonx from makeWritable import makeWritable
endfunction
call s:InitScript()

" mw#perforce#IsInPerforceSandbox: Is this file in a perforce sandbox {{{
function! mw#perforce#IsInPerforceSandbox(fileName)
    let bufferDir = fnamemodify(a:fileName, ':p:h:h')
    let perforcePath = findfile('.perforce', bufferDir . ';')
    return perforcePath != ""
endfunction
" }}}
" mw#perforce#MakeWritable: adds a file to perforce {{{
" Description: 
function! mw#perforce#MakeWritable(fileName)
    if filereadable(a:fileName) && !filewritable(a:fileName)
        " Unletting this variable so that we can re-add this file to
        " perforce. Otherwise, if we have submitted this file via perforce
        " while the file is still open in Vim, we will not re-open the file
        " in perforce when re-writing.
        unlet! b:MW_fileAddedToPerforce

        exec 'pythonx makeWritable("'.a:fileName.'")'
    endif
endfunction " }}}
" mw#perforce#AddFileToPerforce: adds a file to perforce {{{
" Description: 
function! mw#perforce#AddFileToPerforce(fileName)
    if !mw#perforce#IsInPerforceSandbox(a:fileName)
        return
    endif

    if exists('b:MW_fileAddedToPerforce')
        return
    endif
    let b:MW_fileAddedToPerforce = 1

    let cmd = s:scriptDir.'/addToPerforce.py '.a:fileName.' &'
    call system(cmd)
endfunction " }}}
" mw#perforce#RealEditsFile: opens realedits page for a file {{{
" Description: 
function! mw#perforce#RealEditsFile(fileName)
    if !mw#perforce#IsInPerforceSandbox(a:fileName)
        return
    endif
    
    let presRoot = mw#utils#GetRootDir()
    let relPath = strpart(a:fileName, strlen(presRoot)+1)
    echo relPath

    let cmd = 'python -m webbrowser http://p4db/cgi-bin/realEdits/showfile.cgi?f="'.relPath.'"'
    call system(cmd)
endfunction " }}}
