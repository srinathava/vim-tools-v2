" ==============================================================================
" Refactoring commands
" ============================================================================== 

let s:path = expand('<sfile>:p:h')

" mw#refactor#rename:  {{{
" Description: 
function! mw#refactor#rename()
    exec 'pyfile '.s:path.'/clang-rename.py'
endfunction " }}}
