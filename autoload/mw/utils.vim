
" ==============================================================================
" Sandbox utility functions
" ============================================================================== 
" mw#utils#GetRootDir: gets the directory above this one where mw_anchor resides {{{
function! mw#utils#GetRootDir()
    let mw_anchorPath = findfile('mw_anchor', '.;')
    if mw_anchorPath != ''
        return fnamemodify(mw_anchorPath, ':p:h')
    endif

    let gitpath = finddir('.git', '.;')
    if gitpath != ''
        return fnamemodify(gitpath, ':p:h:h')
    endif

    let gitpath = findfile('.git', '.;')
    if gitpath != ''
        return fnamemodify(gitpath, ':p:h')
    endif

    " Do this last otherwise any file under ~ will find this.
    let projpath = findfile('.vimproj.xml', '.;')
    if projpath != ''
        return fnamemodify(projpath, ':p:h')
    end

    return ''
endfunction " }}}
" mw#utils#GetOtherFileName: gets equivalent file in other sandbox {{{
function! mw#utils#GetOtherFileName(otherDir)
    let presRoot = mw#utils#GetRootDir()

    let presFileName = expand('%:p')
    let relPath = strpart(presFileName, strlen(presRoot))

    let otherFileName = a:otherDir.relPath
    if !filereadable(otherFileName)
        return ''
    endif

    return otherFileName
endfunction " }}}
" mw#utils#NormalizeSandbox: normalizes the name of a sandbox {{{
" Description: understands things like "archive"
function! mw#utils#NormalizeSandbox(sb)
    let sb = expand(a:sb)
    if filereadable(sb.'/mw_anchor')
        return sb
    end
    if sb == 'archive'
        let output = system('sbver')
        let archivedir = matchstr(output, 'SyncFrom: \zs\([^ \t\n]\+\)\ze')
        return archivedir
    elseif sb == 'lkg'
        let output = system('sbver')
        let archivedir = matchstr(output, 'Perfect: \zs\([^ \t\n]\+\)\ze')
        return archivedir
    else
        return ''
    endif
endfunction " }}}
" mw#utils#IsInSandbox: Is this file in a sandbox {{{
function! mw#utils#IsInSandbox(fileName)
    let bufferDir = fnamemodify(a:fileName, ':p:h')
    let battreePath = findfile('mw_anchor', bufferDir . ';')
    return battreePath != ""
endfunction
" }}}

" ==============================================================================
" General utility functions
" ============================================================================== 
" mw#utils#AssertError: produces an error if condition is untrue  {{{
function! mw#utils#AssertError(condition, message)
    if !a:condition
        throw a:message
    endif
endfunction " }}}
" mw#utils#SaveSettings: gets the current settings. {{{
function! mw#utils#SaveSettings(settingsList)
    let g:MW_SavedSettings = a:settingsList
    let g:MW_SavedSettingValues = []
    for s in g:MW_SavedSettings
        call add(g:MW_SavedSettingValues, getbufvar('%', '&'.s))
    endfor
endfunction " }}}
" mw#utils#RestoreSettings: resets the settings {{{
function! mw#utils#RestoreSettings()
    for i in range(len(g:MW_SavedSettings))
        call setbufvar('%', '&'.g:MW_SavedSettings[i], g:MW_SavedSettingValues[i])
    endfor
endfunction " }}}

" ChooseFromList:  {{{
" Description: 
function! mw#utils#ChooseFromList(origList, prefix)
    let idx = 1
    let choices = [a:prefix]
    for item in a:origList
        let choices = add(choices, (idx).': '.item)
        let idx += 1
    endfor
    let idxChoice = inputlist(choices)
    if idxChoice <= 0
        return ''
    else
        return a:origList[idxChoice - 1]
    end
endfunction " }}}

" mw#utils#AssertThatWeHaveAValidProject: ensure that there's a valid project {{{
" Description: 
function! mw#utils#AssertThatWeHaveAValidProject()
    let prefix = mw#utils#GetRootDir()
    if prefix == ''
        echohl Error
        echo "You are not in a sandbox. Use :cd to go to a sandbox directory"
        echohl None
        throw "ERROR: Invalid location"
    else
        return
    endif

    let vimProjFile = findfile('.vimproj.xml', '.;')
    if vimProjFile == ''
        let vimProjFile = fnamemodify('~/.vimproj.xml', ':p')
        if !filereadable(vimProjFile)

            let cmd = "cp ".g:MW_rootDir."/vimproj.xml.template ~/.vimproj.xml"
            echohl Error
            echomsg "There is no .vimproj.xml file in either the root of your sandbox"
            echomsg "or your $HOME directory. Please make a copy of:"
            echomsg ""
            echomsg cmd
            echomsg ""
            echomsg "into your $HOME directory and modify it according to your needs"
            echohl None

            echo ""
            let response = input("Do you want me to create ~/.vimproj.xml for you now? y/n: ", "y")
            if response == "y"
                call system(cmd)
                return
            endif

            throw "ERROR: Missing .vimproj.xml file."
        endif
    endif
endfunction " }}}


" vim: fdm=marker
