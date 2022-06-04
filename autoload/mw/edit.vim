pythonx import clang_format

" mw#edit#FormatCurrentSelection: formats current selection {{{
" Description: 
function! mw#edit#FormatCurrentSelection() range
    exec "pythonx clang_format.main()"
endfunction " }}}

