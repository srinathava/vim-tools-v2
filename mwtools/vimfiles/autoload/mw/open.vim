" s:FilterList:  {{{
" Description: 
function! s:FilterList()
    let origPat = @/
    let curpos = getpos('.')

    let pattern = substitute(getline(1), 'Enter pattern: ', '', 'g')

    call mw#debug#Debug('open', 'pattern = '.pattern.', s:pattern = '.s:pattern)

    if stridx(pattern, s:pattern, 0) == -1
        " This is a completely new pattern, so we need to start afresh
        silent! 2,$ d_
        call setline(2, s:allLines)
    end
    let s:pattern = pattern
    if s:pattern != ''
        let pattern = substitute(pattern, ' ', '.*', 'g')
        let pattern = substitute(pattern, '/', '\/', 'g')

        exec 'silent! 2,$ v/'.pattern.'/d_'
        call histdel('search', -1) " do not pollute search history

        if search('^>', 'n') == 0
            call setline(2, substitute(getline(2), '^\s', '>', ''))
        endif
    endif

    call setpos('.', curpos)

    let @/ = origPat
    return ''
endfunction " }}}
" s:MoveSelection: {{{
" Description: 
function! s:MoveSelection(offset)
    let n = search('^>', 'n')
    if n == 0
        let n = 2
    else
        call setline(n, substitute(getline(n), '^>', ' ', ''))
    end
    let n = n + a:offset

    let n = min([n, line('$')])
    let n = max([2, n])

    let nline = getline(n)
    let nline = substitute(nline, '^\s', '>', '')
    call setline(n, nline)
endfunction " }}}
" s:restoreAltBuffer: restore @# so that CTRL-^ works {{{
" Description: 
function! s:restoreAltBuffer()
    let newBufNum = bufnr('%')

    if s:startingBufNum == newBufNum
        exec 'b! '.s:startingAltBufNum
        exec 'b! '.newBufNum
    else
        exec 'b! '.s:startingBufNum
        exec 'b! '.newBufNum
    endif
endfunction " }}}
" s:OpenSelection:  {{{
" Description: 
function! s:OpenSelection()
    let n = search('^>', 'n')
    if n == 0
        let n = 2
    endif
    let fileName = substitute(getline(n), '^\(>\)\=\s*', '', '')
    let fileName = b:textToAdd . fileName

    let tmpBufNum = bufnr('%')

    exec 'e '.fileName
    call s:restoreAltBuffer()
endfunction " }}}
" s:MapSingleKey:  {{{
" Description: 
function! s:MapSingleKey(key)
    exec 'inoremap <silent> <buffer> '.a:key.' '.a:key.'<C-R>=<SID>FilterList()<CR>'
endfunction " }}}
" s:SafeBackspace:  {{{
" Description: 
function! s:SafeBackspace()
    if col('.') > 16
        return "\<bs>"
    else
        return ""
    endif
endfunction " }}}
" s:CloseToolWindow: close tool window when user presses <esc> {{{
" Description: 
function! s:CloseToolWindow()
    " bd! works better than "e #" if @# has not been set yet (for instance
    " if we started filtering with no files open yet)
    bd!
    call s:restoreAltBuffer()
endfunction " }}}
" s:MapKeys:  {{{
" Description: 
function! s:MapKeys()
    setlocal hls
    for i in range(26)
        call s:MapSingleKey(nr2char(char2nr('a') + i)) 
        call s:MapSingleKey(nr2char(char2nr('A') + i)) 
    endfor
    for i in range(10)
        call s:MapSingleKey(nr2char(char2nr('0') + i))
    endfor
    call s:MapSingleKey('_')
    call s:MapSingleKey('<space>')
    call s:MapSingleKey('<del>')

    inoremap <buffer> <silent> <bs>     <C-r>=<sid>SafeBackspace()<CR><C-r>=<sid>FilterList()<CR>

    inoremap <buffer> <silent> <C-p>    <C-o>:call <sid>MoveSelection(-1)<CR>
    inoremap <buffer> <silent> <C-k>    <C-o>:call <sid>MoveSelection(-1)<CR>
    inoremap <buffer> <silent> <Up>     <C-o>:call <sid>MoveSelection(-1)<CR>

    inoremap <buffer> <silent> <C-n>    <C-o>:call <sid>MoveSelection(1)<CR>
    inoremap <buffer> <silent> <C-j>    <C-o>:call <sid>MoveSelection(1)<CR>
    inoremap <buffer> <silent> <Down>   <C-o>:call <sid>MoveSelection(1)<CR>

    inoremap <buffer> <silent> <CR>     <esc>:call <sid>OpenSelection()<CR>

    inoremap <buffer> <silent> <esc>    <esc>:call <sid>CloseToolWindow()<CR>
    nnoremap <buffer> <silent> <esc>    :call <sid>CloseToolWindow()<CR>

    " Avoids weird problems in terminal vim
    inoremap <buffer> <silent> A <Nop>
    inoremap <buffer> <silent> B <Nop>
    nnoremap <buffer> <silent> A <Nop>
    nnoremap <buffer> <silent> B <Nop>
endfunction " }}}
" StartFiltering:  {{{
" Description: 
function! mw#open#StartFiltering()
    call matchadd('Search', '^>.*')
    let s:pattern = ''
    let s:allLines = getline(0, '$')
    call s:MapKeys()
    0put='Enter pattern: '
    startinsert!
endfunction " }}}

" mw#open#OpenFile: opens a file in the solution {{{
" Description: 
function! mw#open#OpenFile()
    call mw#utils#AssertThatWeHaveAValidProject()

    let prefix = mw#utils#GetRootDir()
    let filelist = system('listFiles.py')

    let s:startingBufNum = bufnr('%')
    let s:startingAltBufNum = bufnr('#')

    drop _MW_Files_
    let bufnum = bufnr('%')
    call setbufvar(bufnum, '&swapfile', 0)
    call setbufvar(bufnum, '&buflisted', 0)
    call setbufvar(bufnum, '&buftype', 'nofile')
    call setbufvar(bufnum, '&ts', 8)

    let origPat = @/
    silent! 0put=filelist

    silent! %s/^/    /g
    call histdel('search', -1)

    exec 'silent! %s/'.escape(prefix, '/').'//'
    call histdel('search', -1)

    let b:textToAdd = prefix

    call mw#open#StartFiltering()
    let @/ = origPat
endfunction " }}}
