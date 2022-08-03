let s:scriptDir = expand('<sfile>:p:h')

function! LogDebug(msg)
    let logger_enabled = exists('g:termdebug_logger_enabled') && g:termdebug_logger_enabled
    if !logger_enabled
        return{}
    endif
    call mw#initpy#Init()
    pythonx import sys
    exec 'pythonx sys.path += [r"'.s:scriptDir.'"]'
    pythonx from init_logging import log
    exec 'pythonx log(r"'.a:msg.'")'
endfunction


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
        if exists('g:sbgdbpath')
            "using user specified gdb
            "using vim-tools/plugin/.gdbinit
            return split('sb -debug-exe '.g:sbgdbpath.' -s '.sbroot.' -debug -no-debug-backing-stores -gdb-switches -x -gdb-switches '.s:scriptDir.'/.gdbinit -gdb-switches -quiet', ' ')
        else
            "using sbtools default gdb (gdb-121 as of 7/5/2022)
            "using vim-tools/plugin/.gdbinit
            return split('sb -s '.sbroot.' -debug -no-debug-backing-stores -gdb-switches -x -gdb-switches '.s:scriptDir.'/.gdbinit -gdb-switches -quiet', ' ')
        endif
    elseif executable('sbgdb')
        return ['sbgdb']
    elseif exists('g:termdebugger')
        return [g:termdebugger]
    else
        return ['gdb']
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
        let input = input('Enter the PID or process name to attach to :')
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
    let s:on_gdb_started = 'GDB '.a:method.' '.pid
    if s:termdebug_status == 'stopped'
        "Attach or QuickAttach is called without starting GDB
        Termdebug
    else
        "Attach or QuickAttach is called after starting GDB
        exec s:on_gdb_started
        return
    end

    augroup TermdebugWrapperAttach
        au!
        au User TermDebugStarted exec s:on_gdb_started
    augroup END

endfunction " }}}

let s:termdebug_status = 'stopped'
" s:OnTermDebugStarted: triggered when Termdebug has started GDB {{{
" Description: 
function! s:OnTermDebugStarted()
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

augroup TermDebugWrapper
    au!
    au User TermDebugStarted :call s:OnTermDebugStarted()
    au User TermDebugStopped :call s:OnTermDebugStopped()
augroup END
nmap <F9> :ToggleBreakpoint<CR>

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
  call s:CreateMap('<F12>',   ':GDB finish<CR>', 'n')
  call s:CreateMap('U',       ':call TermDebugUpStack()<CR>', 'n')
  call s:CreateMap('D',       ':call TermDebugDownStack()<CR>', 'n')
  call s:CreateMap('<C-P>',   ':call TermDebugPrintHelper(0)<CR>', 'n')
  call s:CreateMap('<C-P>',   'y:call TermDebugPrintHelper(1)<CR>', 'v')
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
let g:termdebugger = 'gdb'
let g:termdebug_popup = 0
let g:termdebug_install_winbar = 0

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
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Next<Tab><F10>', ':Over<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Step\ &Out<Tab>Shift-<F11>', ':Finish<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Until', ':Until<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Run', ':Run<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Continue<Tab><F5>', ':Continue<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Interrupt<Tab>Ctrl-C', ':Stop<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Kill<Tab>Shift+<F5>', ':GDB kill<CR>')

    amenu &Gdb.-sep3-      <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.Sho&w\ C\ Stack', ':Stack<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Show\ &MATLAB\ Stack', ':StackM<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Show\ H&ybrid\ Stack', ':StackH<CR>')

    amenu &Gdb.-sep4-      <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.&Up\ Stack\ (caller)<Tab>U', ':call TermDebugUpStack()<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Down\ Stack\ (callee)<Tab>D', ':call TermDebugDownStack()<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.&Goto\ Frame', ':GDB frame ')

    amenu &Gdb.-sep5-      <Nop>

    " print value at cursor
    call s:InstallRuntimeMenuItem('n', '&Gdb.&Print\ Value<Tab>Ctrl-P', ':call TermDebugPrintHelper(0)<CR>')
    call s:InstallRuntimeMenuItem('v', '&Gdb.&Print\ Value<Tab>Ctrl-P', 'y:call TermDebugPrintHelper(1)<CR>')
    call s:InstallRuntimeMenuItem('n', '&Gdb.Run\ Command', ':GDB<Space>')

    amenu &Gdb.-sep6- <Nop>


    amenu &Gdb.-sep7- <Nop>

    call s:InstallRuntimeMenuItem('a', '&Gdb.Show\ C\ Stack\ (&Load\ Symbols)', ':LoadAndShowStack<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Handle\ SIGSEGV', ':GDB handle SIGSEGV stop print<CR>')
    call s:InstallRuntimeMenuItem('a', '&Gdb.Ignore\ SIGSEGV', ':GDB handle SIGSEGV nostop noprint<CR>')
endfunction " }}}


command! -nargs=? Attach      :call s:TermdebugAttach(<q-args>, 'attach')
command! -nargs=? QuickAttach :call s:TermdebugAttach(<q-args>, 'quick_attach_sf')

if has('gui_running')
    amenu &Gdb.Start\ Gdb               :Termdebug<CR>
    call s:InstallRuntimeMenuItem('a', '&Gdb.S&how\ GDB\ Terminal', ':ShowGdb<CR>')
    amenu &Gdb.&Attach        :Attach<CR>
    amenu &Gdb.&Quick\ Attach :QuickAttach<CR>

    amenu &Gdb.-sep1- <Nop>

    amenu &Gdb.&Toggle\ Breakpoint<Tab><F9>      :ToggleBreakpoint<CR>

    call s:InstallRuntimeMenuItems()
    call s:DisableRuntimeMenuItems()
endif

