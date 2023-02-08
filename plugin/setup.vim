syntax on
filetype plugin on
filetype indent on
source $VIMRUNTIME/macros/matchit.vim

set ts=8 sw=4 et bs=2 sts=4

set mousemodel=popup
set shell=bash " needed by DiffSubmitFile

com! -nargs=0 CD :exec 'cd '.expand('%:p:h')

if !has('nvim')
    map <F3> <Plug>StartBufExplorer
    map <S-F3> <Plug>SplitBufExplorer
endif

set diffexpr=MyDiff()
function! MyDiff()
    let opt = ""
    if &diffopt =~ "icase"
        let opt = opt . "-i "
    endif
    if &diffopt =~ "iwhite"
        let opt = opt . "-w "
    endif
    silent execute "!diff -a --binary " . opt . v:fname_in . " " . v:fname_new .
        \  " > " . v:fname_out
endfunction

let g:MW_rootDir = expand('<sfile>:p:h:h')
