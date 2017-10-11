let b:tag_if = "if (<++>) {\<CR><++>\<CR>}"
let b:tag_for = "for (<++>; <++>; <++>) {\<CR><++>\<CR>}"
let b:tag_else = "else {\<CR><++>\<CR>}"
imap <silent> <buffer> <C-e> <C-r>=C_CompleteWord()<CR>

let g:clang_format_path = 'sb-clang-format'
exec 'vnoremap <silent> <Plug>clang-format :pyfile '.g:MW_rootDir.'/pytools/clang-format.py<CR>'

if !hasmapto('<Plug>clang-format', 'v')
    vmap <silent> = <Plug>clang-format
endif

if exists('b:did_mw_c_ftplugin')
    finish
endif

let b:did_mw_c_ftplugin = 1
call mw#tag#AddSandboxTags(expand('%:p'))
let Tlist_Process_File_Always = 1
let Tlist_Auto_Update = 1
TlistUpdate
set statusline=%<%f\ %m%r%h%(%{GetCurrentTagOrEmpty()}%)%=%l,%c\ (%p%%)

if exists('*ToggleSrcHeader')
    finish
endif

" ==============================================================================
" Only function / command definitions below here!
" ============================================================================== 

" ToggleSrcHeader: toggles between a .h and .c file  {{{
" (as long as they are in the same directory)
function! ToggleSrcHeader()
    let fname = expand('%:p:r')
    let ext = expand('%:e')
    if ext =~ '[cC]'
        let other = glob(fname.'.h*')
    else
        let other = glob(fname.'.c*')
    endif
    let other = split(other, '\n\|\r')[0]
    if strlen(other) > 0
        exec 'drop '.other
    endif
endfunction " }}}

command! -nargs=0 EH :call ToggleSrcHeader()

" CompleteTag: makes a tag from last word {{{
function! C_CompleteWord()
    let line = strpart(getline('.'), 0, col('.')-1)

    let word = matchstr(line, '\w\+$')
    if word != '' && exists('b:tag_'.word)
        let back = substitute(word, '.', "\<BS>", 'g')
        return IMAP_PutTextWithMovement(back.b:tag_{word})
    else
        return ''
    endif
endfunction " }}}

" GetCurrentTagOrEmpty:  {{{
" Description: 
function! GetCurrentTagOrEmpty()
    let txt = Tlist_Get_Tagname_By_Line()
    if txt == ''
        return txt
    else
        return '['.txt.']'

endfunction " }}}
