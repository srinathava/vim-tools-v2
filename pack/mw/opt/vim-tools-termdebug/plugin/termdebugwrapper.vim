" TermdebugFilenameModifier: modifies the file name for setting breakpoints {{{
"Description: 
function! TermdebugFilenameModifier(filepath)
    let filepath = a:filepath

    let sbroot = findfile('mw_anchor', filepath.';')
    if sbroot != ''
        let sbroot = fnamemodify(sbroot, ':p:h')
        let mlroot = sbroot . '/matlab/'
        let filepath = filepath[strlen(mlroot):]
    endif
    return fnameescape(filepath)
endfunction " }}}
" TermDebugGdbCmd: return full gdb command {{{
" Description: 
function! TermDebugGdbCmd(pty)
    let mw_anchor_loc = findfile('mw_anchor', '.;')
    if mw_anchor_loc != ''
        let sbroot = fnamemodify(mw_anchor_loc, ':h')
        return split('sb -s '.sbroot.' -debug -no-debug-backing-stores -gdb-switches -quiet', ' ')
    else
        return ['sbgdb']
    endif
endfunction " }}}

" s:GetPidFromName: gets the PID from the name of a program {{{
function! s:GetPidFromName(name)
    let ps = system('ps -u '.$USER.' | grep -w '.a:name.' | grep -v "<defunct>"')
    if ps == ''
        echohl ErrorMsg
        echo "No running '".a:name."' process found"
        echohl NOne
        return ''
    end

    let pslines = split(ps, '\n')
    if len(pslines) == 1
        return matchstr(ps, '^\s*\zs\d\+')
    end

    if len(pslines) > 1
        if !isdirectory('/proc') || $DISPLAY == ''
            echohl ErrorMsg
            echo "Too many running '".a:name."' processes. Don't know which to attach to. Use a PID."
            echohl None
            return ''
        end


        let pidsOnThisDisplay = []

        for psline in pslines
            let pid = matchstr(psline, '^\s*\zs\d\+')
            let envfile = '/proc/'.pid.'/environ'
            if filereadable(envfile)
                let envContents = readfile(envfile, 'b')[0]
                let displayNum = matchstr(envContents, 'DISPLAY=\zs[^\o0]\+')
                if displayNum == $DISPLAY
                    call add(pidsOnThisDisplay, pid)
                end
            end
        endfor

        if len(pidsOnThisDisplay) == 1
            echohl WarningMsg
            echomsg "Attaching to PID ".pidsOnThisDisplay[0]." because that is the only PID on this display."
            echohl None

            return pidsOnThisDisplay[0]
        else
            echohl ErrorMsg
            echo "Too many running '".a:name."' processes on this $DISPLAY. Don't know which to attach to. Use a PID."
            echohl None
            return ''
        end
    end
endfunction

function! s:TermdebugAttach(pid, method)
    let pid = a:pid
    if pid == ''
        let input = input('Enter the PID or process name to attach to :', 'MATLAB')
    else
        let input = pid
    endif
    if input =~ '^\d\+$'
        let pid = input
    else
        let pid = s:GetPidFromName(input)
    endif
    if pid !~ '^\d\+$'
        return
    end
    if s:termdebug_status == 'stopped'
        Termdebug
    endif
    exec 'GDB '.a:method.' '.pid
endfunction " }}}

" s:SetupHighlighting:  {{{
function! s:SetupHighlighting()
    hi default debugBreakpointPending term=reverse ctermbg=red guibg=red
endfunction " }}}

call s:SetupHighlighting()

au ColorScheme * call s:SetupHighlighting()

sign define debugBreakpointPending text=? texthl=debugBreakpointPending

" s:ToggleBreakpoint: sets/clears pending breakpoint before Termdebug has started {{{
" Description: 
let s:numBreakpoints = 0
function! s:ToggleBreakpoint()
    let setBpInfo = sign_getplaced(bufname(), {'group': 'TermDebugBreakpoints', 'lnum': line('.')})

    if !empty(setBpInfo[0]['signs'])
        " There's already a breakpoint set by core termdebug. Let it handle
        " toggling the breakpoint
        ToggleBreakpoint
        return
    endif

    let info = sign_getplaced(bufname(), {'group': 'TermDebugPendingBreakpoints', 'lnum': line('.')})
    if empty(info[0]['signs'])

        call sign_place(s:numBreakpoints+1, 
                    \ 'TermDebugPendingBreakpoints', 'debugBreakpointPending', '%', {
                    \ 'lnum': line('.'),
                    \ })
        let s:numBreakpoints += 1
    else
        echomsg info
        call sign_unplace('TermDebugPendingBreakpoints', {'buffer': bufname(), 'id': info[0]['signs'][0]['id']})
    endif
endfunction " }}}
" s:GetAllBreakPoints:  {{{
function! s:GetAllBreakPoints()
    let bps = []
    for bufnr in range(1, bufnr('$'))
        if !buflisted(bufnr) || empty(bufname(bufnr))
            continue
        endif
        let signs = sign_getplaced(bufname(bufnr), {'group': 'TermDebugPendingBreakpoints'})
        let signs = signs[0]['signs']
        for sign in signs
            let bps += [{'fname': expand('#'.bufnr.':p'), 'lnum': sign['lnum']}]
        endfor
    endfor
    return bps
endfunction " }}}

let s:termdebug_status = 'stopped'
" s:OnTermDebugStarted: triggered when Termdebug has started GDB {{{
" Description: 
function! s:OnTermDebugStarted()
    let bps = s:GetAllBreakPoints()
    for bp in bps
        call s:Debug("OnTermDebugStarted: restoring breakpoint")
        let fname = TermdebugFilenameModifier(bp['fname'])
        call TermDebugSendCommand("break ".fname.':'.bp['lnum'])
    endfor
    call sign_unplace('TermDebugPendingBreakpoints')

    call s:InstallMaps()
    call s:EnableRuntimeMenuItems()

    amenu 80.5 PopUp.Run\ to\ cursor\ (GDB) :Until<CR>
    amenu 80.5 PopUp.Jump\ to\ cursor\ (GDB) :Jump<CR>
    amenu 80.7 PopUp.-sep-gdb0- <Nop>

    let s:termdebug_status = 'running'
endfunction " }}}
" s:OnTermDebugStopped: triggered when Termdebug is stopping {{{
" Description: 
function! s:OnTermDebugStopped()
    call s:RestoreMaps()
    call s:DisableRuntimeMenuItems()

    aunmenu PopUp.Run\ to\ cursor\ (GDB)
    aunmenu PopUp.Jump\ to\ cursor\ (GDB)
    aunmenu PopUp.-sep-gdb0-

    let s:termdebug_status = 'stopped'
endfunction " }}}

augroup TermDebugPendingBreakpoint
    au User TermDebugStarted :call s:OnTermDebugStarted()
    au User TermDebugStopped :call s:OnTermDebugStopped()
augroup END
" This map will be taken over by Termdebug once it has started.
nmap <F9> :call <SID>ToggleBreakpoint()<CR>

let s:userMappings = {}

" s:CreateMap: sets up a user map {{{
function! s:CreateMap(key, rhs, mode)
  let s:userMappings[a:mode . a:key] = maparg(a:key, a:mode)
  exec a:mode.'map <silent> '.a:key.' '.a:rhs
endfunction " }}}
" s:InstallMaps: installs default VSCode style maps {{{
func! s:InstallMaps()
  if !exists('g:termdebug_install_maps') || !g:termdebug_install_maps
    return
  endif
  call s:CreateMap('<C-c>',   ':Stop<CR>', 'n')
  call s:CreateMap('<F5>',    ':Continue<CR>', 'n')
  call s:CreateMap('<S-F5>',  ':GDB kill<CR>', 'n')
  call s:CreateMap('<F10>',   ':Over<CR>', 'n')
  call s:CreateMap('<F11>',   ':Step<CR>', 'n')
  call s:CreateMap('<S-F11>', ':GDB finish<CR>', 'n')
  call s:CreateMap('U',       ':GDB up<CR>', 'n')
  call s:CreateMap('D',       ':GDB down<CR>', 'n')
  call s:CreateMap('<F9>',    ':ToggleBreakpoint<CR>', 'n')
  call s:CreateMap('<C-P>',   ":exec 'GDB print '.expand('<cword>')<CR>", 'n')
  call s:CreateMap('<C-P>',   'y:GDB print <C-R>"<CR>', 'v')
endfunction " }}}
" s:RestoreMaps: restores user maps {{{
function! s:RestoreMaps()
  for item in keys(s:userMappings)
    let mode = item[0]
    let lhs = item[1:]
    let rhs = s:userMappings[item]
    if rhs != ''
      exec mode.'map <silent> '.lhs.' '.rhs
    else
      exec mode.'unmap '.lhs
    endif
  endfor
endfunction " }}}

let g:termdebug_separate_tty = 0
let g:termdebug_persist_breakpoints = 1
let g:termdebug_install_maps = 1
let g:termdebugger = 'sbgdb'
let g:termdebug_popup = 0
let g:termdebug_install_winbar = 0

command! -nargs=0 InitGdb Termdebug

" s:InstallRuntimeMenuItem:  {{{
" Description: 
let s:runtimeMenuItems = []
function! s:InstallRuntimeMenuItem(mode, lhs, rhs)
    exec a:mode.'menu '.a:lhs.' '.a:rhs
    call add(s:runtimeMenuItems, {'mode': a:mode, 'lhs': a:lhs, 'rhs': a:rhs})
endfunction " }}}
" s:DisableRuntimeMenuItems:  {{{
" Description: 
function! s:DisableRuntimeMenuItems()
    for item in s:runtimeMenuItems
        exec item['mode'].'menu disable '.item['lhs']
    endfor
endfunction " }}}
" s:EnableRuntimeMenuItems:  {{{
" Description: 
function! s:EnableRuntimeMenuItems()
    for item in s:runtimeMenuItems
        exec item['mode'].'menu enable '.item['lhs']
    endfor
endfunction " }}}

" InstallRuntimeMenuItems: install menu relevant to a running GDB {{{
" Description: 
function! s:InstallRuntimeMenuItems()
    amenu &Gdb.-sep2- <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.&Step\ Into<Tab><F11>', ':Step<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Next<Tab><F10>', ':Next<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Step\ &Out<Tab>Shift-<F11>', ':Finish<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Until', ':Until<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Run', ':Run<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Continue<Tab><F5>', ':Continue<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Interrupt<Tab>Ctrl-C', ':Stop<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Kill<Tab>Shift+<F5>', ':GDB kill<CR>')

    amenu &Gdb.-sep3-      <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.&Up\ Stack\ (caller)<Tab>U', ':GDB up<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Down\ Stack\ (callee)<Tab>D', ':GDB down<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Goto\ Frame', ':GDB frame ')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Sho&w\ Stack', ':Stack<CR>')

    amenu &Gdb.-sep4-      <Nop>

    " print value at cursor
    call s:InstallRuntimeMenuItem('n', '&Gdb.&Print\ Value<Tab>Ctrl-P', ':exec "GDB print ".expand("<cword>"))<CR>')
    call s:InstallRuntimeMenuItem('v', '&Gdb.&Print\ Value', 'y:GDB print <C-R>""<CR>')
    call s:InstallRuntimeMenuItem('n', '&Gdb.Run\ Command', ':GDB<Space>')

    amenu &Gdb.-sep5- <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.Handle\ SIGSEGV', ':GDB handle SIGSEGV stop print<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Ignore\ SIGSEGV', ':GDB handle SIGSEGV nostop noprint<CR>')
endfunction " }}}


command! -nargs=? Attach      :call s:TermdebugAttach(<q-args>, 'attach')
command! -nargs=? QuickAttach :call s:TermdebugAttach(<q-args>, 'quick_attach_sf')

if has('gui_running')
    amenu &Gdb.Start\ Gdb               :Termdebug<CR>
    call s:InstallRuntimeMenuItem('a', '&Gdb.Show\ GDB\ Ter&minal', ':ShowGdb<CR>')
    amenu &Gdb.&Attach        :Attach<CR>
    amenu &Gdb.&Quick\ Attach :QuickAttach<CR>

    amenu &Gdb.-sep1- <Nop>

    amenu &Gdb.&Toggle\ Breakpoint<Tab><F9>      :ToggleBreakpoint<CR>

    call s:InstallRuntimeMenuItems()
    call s:DisableRuntimeMenuItems()
endif

func s:Debug(msg)
  exec "pyx log(r'''".a:msg."''')"
endfunction
