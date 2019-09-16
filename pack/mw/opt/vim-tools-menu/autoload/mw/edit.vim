call MW_ExecPython('import clang_format')

" mw#edit#FormatCurrentSelection: formats current selection {{{
" Description: 
function! mw#edit#FormatCurrentSelection() range
    call MW_ExecPython("clang_format.main()")
endfunction " }}}

