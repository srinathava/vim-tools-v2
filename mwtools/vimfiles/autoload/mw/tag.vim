let s:scriptDir = expand('<sfile>:p:h')
function! s:InitScript()
    call MW_ExecPython("import sys")
    call MW_ExecPython("import vim")
    call MW_ExecPython('sys.path += [r"'.s:scriptDir.'"]')
    call MW_ExecPython("from addSandboxTags import addSandboxTags, getTagFiles")
endfunction
call s:InitScript()

let s:path = expand('<sfile>:p:h')
" mw#tag#AddSandboxTags: add all tags for a given C/C++ file {{{
function! mw#tag#AddSandboxTags(fname)
    let &l:tags = s:.path.'/cpp_std.tags'
    call MW_ExecPython('addSandboxTags(r"'.a:fname.'")')
endfunction " }}}
" mw#tag#InitVimTags:  {{{
" Description: 
function! mw#tag#InitVimTags()
    call mw#utils#AssertThatWeHaveAValidProject()

    !genVimTags.py
    call mw#tag#AddSandboxTags(expand('%:p'))
endfunction " }}}
" mw#tag#SelectTag: select a tag from this project {{{
" Description: 
function! mw#tag#SelectTag(fname)
    if a:fname == ""
        echohl Error
        echo "You need to open a file in some project to use this tool."
        echohl None
        return
    endif

    call mw#utils#AssertThatWeHaveAValidProject()

    let tagsFile = MW_EvalPython('getTagFiles(r"'.a:fname.'")')
    let output = system('selectTag.py '.tagsFile)
    let [tagName, fileName, tagPattern] = split(output, "\n")

    let tagsFilePath = fnamemodify(tagsFile, ':p:h')
    let fileName = tagsFilePath . '/' . fileName

    exec 'drop '.fileName
    let tagPattern = escape(tagPattern, '*[]')
    exec tagPattern
endfunction " }}}

" ==============================================================================
" Utilities for automatically adding required header.
" ============================================================================== 
" mw#tag#AddIncludeImpl: add include for word under cursor {{{
" Description: 
function! mw#tag#AddIncludeImpl(currentFilePath, word)
    let currentModulePath = findfile('MODULE_DEPENDENCIES', a:currentFilePath.';')
    let currentModulePath = substitute(currentModulePath, 'MODULE_DEPENDENCIES$', '', '')

    let tags = taglist('\C^'.a:word.'$')

    let fileNamesMap = {}
    for tag_ in tags
        let fileName = tag_['filename']
        if fileName =~ '.h\(pp\)\?$'
            if fileName =~ 'export\/include'
                let fileName = substitute(fileName, '.*export\/include\/', '', 'g')
            elseif fileName =~ currentModulePath
                let fileName = substitute(fileName, currentModulePath, '', 'g')
            end
            let fileNamesMap[fileName] = 1
        end
    endfor

    let fileNameList = keys(fileNamesMap)
    if len(fileNameList) == 0
        echomsg "No declarations of this symbol found in any header file"
        return
    endif

    if len(fileNameList) > 1
        let fileName = mw#utils#ChooseFromList(fileNameList, 'Multiple possible includes found. Please choose one')
    else
        let fileName = fileNameList[0]
    end

    if fileName != ''
        call mw#tag#IncludeFileNameInNicePlace(fileName)
    endif
endfunction " }}}
" mw#tag#AddIncludeInSource: add include for word under cursor {{{
" Description: 
function! mw#tag#AddIncludeInSource()
    let currentFilePath = expand('%:p:h')
    let word = expand('<cword>')
    call mw#tag#AddIncludeImpl(currentFilePath, word)
endfunction " }}}
" mw#tag#AddIncludeInQuickfix: add include for word under cursor {{{
" Description: 
function! mw#tag#AddIncludeInQuickfix()
    let word = expand('<cword>')
    exec "normal! \<CR>"
    let currentFilePath = expand('%:p:h')
    call mw#tag#AddIncludeImpl(currentFilePath, word)
    wincmd w
endfunction " }}}
" mw#tag#AddInclude: add include for word under cursor {{{
" Description: 
function! mw#tag#AddInclude()
    if &ft == 'qf'
        call mw#tag#AddIncludeInQuickfix()
    else
        call mw#tag#AddIncludeInSource()
    endif
endfunction " }}}
" mw#tag#IncludeFileNameInNicePlace:  {{{
" Description: 
function! mw#tag#IncludeFileNameInNicePlace(fileName)
    let save_cursor = getcurpos()

    let neededInclude = '#include "'.a:fileName.'"'

    if search(neededInclude, 'wn') > 0
        echohl WarningMsg
        echomsg "\"".a:fileName."\" is already included."
        echohl None
        return
    end

    call cursor(1, 1)

    let includeList = [neededInclude]
    while 1
        let pos = search('^#include "', 'W')
        if pos == 0
            break
        endif

        let includeList = add(includeList, getline('.'))
    endwhile

    let sortedIncludeList = sort(includeList)
    let idx = 0
    for includeLine in sortedIncludeList
        if includeLine == neededInclude
            break
        end
        let idx += 1
    endfor

    let lastIdx = len(sortedIncludeList) - 1
    if idx == lastIdx
        " Even if the list has only 1 element, this still works because
        " VimL allows negative indexing. For a list with 1 element list[0]
        " and list[-1] are equivalent.
        let nearbyInclude = sortedIncludeList[lastIdx-1]
        let putAfter = 1
    else
        let nearbyInclude = sortedIncludeList[idx + 1]
        let putAfter = 0
    end

    call cursor(1, 1)
    let pos = search(nearbyInclude, 'n')
    if !putAfter
        let pos = pos - 1
    endif

    call append(pos, neededInclude)
    call cursor(pos+1, 1)

    let save_cursor[1] += 1 " index 1 stores the line number
    call setpos('.', save_cursor)

    redraw " This is needed to ensure that this message does not dissapear

    echohl WarningMsg
    echomsg 'Adding ['.neededInclude.']'
    echohl None
endfunction " }}}

" vim: fdm=marker
