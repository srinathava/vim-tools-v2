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
    let newBufName = bufname('%')

    if s:startingBufName == newBufName
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
    " This long complicated procedure is all because Vim doesn't allow us
    " to just set @# :(
    "
    " This complicated procedure is to make things work when we press <esc>
    " in various complicated scenarios:
    " . The user starts Open from a [No Name] buffer
    " . The user starts Open with several windows open
    " . The user starts Open with the same buffer open in multiple windows
    
    " 1. We first split open a new [No Name] buffer. Remember the window
    " number of [No Name] when it opens.
    new
    let tempWinNr = winnr()

    " 2. We then return to the _MW_FILES_ buffer
    wincmd w

    " 3. We issue bd! on this _MW_FILES_ buffer
    " This brings us back to [No Name]. We ensure that we are in [No Name]
    " by using tempWinNr
    bd!
    exec tempWinNr.' wincmd w'

    " 5. We then try to restore the startingBufNum and altBufNum from this
    " state. The reason for opening a new noname buffer and then closing
    " _MW_FILES_ is to make sure we do not unecessarily change the window
    " layout etc.
    if s:startingBufName != ''
        exec 'e #'.s:startingBufNum
    endif
    if s:startingAltBufNum != -1
        call s:restoreAltBuffer()
    endif
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
    if filereadable(prefix . '/mw_anchor')
        let filelist = system('listFiles.py')
    else
        if executable('fd')
            let filelist = system('fd --type f . '.prefix)
        elseif executable('fdfind')
            let filelist = system('fdfind --type f . '.prefix)
        else
            let filelist = system('find -type f -not -path ".git/*" '.prefix)
        endif
    endif

    let s:startingBufName = bufname('%')
    let s:startingBufNum = bufnr('%')
    let s:startingAltBufNum = bufnr('#')

    drop _MW_Files_
    let bufnum = bufnr('%')
    call setbufvar(bufnum, '&swapfile', 0)
    call setbufvar(bufnum, '&buflisted', 0)
    call setbufvar(bufnum, '&buftype', 'nofile')
    call setbufvar(bufnum, '&ts', 8)
    call setbufvar(bufnum, '&filetype', 'MW_FILES')

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
