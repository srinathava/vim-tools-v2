" Debugger plugin using gdb.
"
" Author: Bram Moolenaar
" Copyright: Vim license applies, see ":help license"
" Last Change: 2020 Oct 25
"
" WORK IN PROGRESS - Only the basics work
" Note: On MS-Windows you need a recent version of gdb.  The one included with
" MingW is too old (7.6.1).
" I used version 7.12 from http://www.equation.com/servlet/equation.cmd?fa=gdb
"
" There are two ways to run gdb:
" - In a terminal window; used if possible, does not work on MS-Windows
"   Not used when g:termdebug_use_prompt is set to 1.
" - Using a "prompt" buffer; may use a terminal window for the program
"
" For both the current window is used to view source code and shows the
" current statement from gdb.
"
" USING A TERMINAL WINDOW
"
" Opens two visible terminal windows:
" 1. runs a pty for the debugged program, as with ":term NONE"
" 2. runs gdb, passing the pty of the debugged program
" A third terminal window is hidden, it is used for communication with gdb.
"
" USING A PROMPT BUFFER
"
" Opens a window with a prompt buffer to communicate with gdb.
" Gdb is run as a job with callbacks for I/O.
" On Unix another terminal window is opened to run the debugged program
" On MS-Windows a separate console is opened to run the debugged program
"
" The communication with gdb uses GDB/MI.  See:
" https://sourceware.org/gdb/current/onlinedocs/gdb/GDB_002fMI.html
"
" Modifications by Srinath Avadhanula:
" # Pending breakpoints
" # Stack window
" # Neovim and vim compatible
" # More flexibility for choosing g:termdebugger
" # Some bug-fixes (probably specific to my usage/workflow)
" # Probably badly broke the promptbuffer part of this.

let s:scriptDir = expand('<sfile>:p:h')
function! s:InitDebugLogging()
    call mw#initpy#Init()
    pythonx import sys
    exec 'pythonx sys.path += [r"'.s:scriptDir.'"]'
    pythonx from init_logging import initLogging
    exec 'pythonx initLogging()'
endfunction
call s:InitDebugLogging()

" Need either the +terminal feature or +channel and the prompt buffer.
" The terminal feature does not work with gdb on win32.
if (has('nvim') || has('terminal')) && !has('win32')
  let s:way = 'terminal'
elseif has('channel') && exists('*prompt_setprompt')
  let s:way = 'prompt'
else
  if has('terminal')
    let s:err = 'Cannot debug, missing prompt buffer support'
  else
    let s:err = 'Cannot debug, +channel feature is not supported'
  endif
  command -nargs=* -complete=file -bang Termdebug echoerr s:err
  command -nargs=+ -complete=file -bang TermdebugCommand echoerr s:err
  finish
endif

let s:keepcpo = &cpo
set cpo&vim

" The command that starts debugging, e.g. ":Termdebug vim".
" To end type "quit" in the gdb window.
command -nargs=* -complete=file -bang Termdebug call s:StartDebug(<bang>0, <f-args>)
command -nargs=+ -complete=file -bang TermdebugCommand call s:StartDebugCommand(<bang>0, <f-args>)

" Name of the gdb command, defaults to "gdb".
if !exists('g:termdebugger')
  let g:termdebugger = 'gdb'
endif

" Define global variables. Allow re-sourcing file without resetting script
" local variables.
if !exists('g:termdebug_reset_vars') || g:termdebug_reset_vars
  let g:termdebug_reset_vars = 0

  let s:gdb_started = 0
  let s:breakpoints = {}

  let s:breakpoint_signs = {}
  let s:winbar_winids = []

  let s:ignoreEvalError = 0
  let s:evalFromBalloonExpr = 0
  let s:pendingOutput = ''

  let s:pc_id = 12
  let s:asm_id = 13
  let s:break_id = 13  " breakpoint number is added to this
  let s:stopped = 1

  let s:parsing_disasm_msg = 0
  let s:asm_lines = []
  let s:asm_addr = ''

  let s:collecting_hybrid_stack = 0
  let s:hybrid_stack = ''

  let s:debug_log = ''
  let s:stoppedInMATLAB = v:false
  let s:MLBreakpoints = {}


  let s:current_frame_type = ''
  let s:current_frame_idx = -1
  let s:current_stack_type = ''

  let s:pending_breakpoint_files = {}
  let s:pending_breakpoint_dlls = {}
  let s:gdbstatus = ''
  let s:evalexpr = ''
endif

func! s:Debug(msg)
  let s:debug_log .= a:msg . "\n"
endfunction
command -nargs=0 TermLog :echo s:debug_log

" Take a breakpoint number as used by GDB and turn it into an integer.
" The breakpoint may contain a dot: 123.4 -> 123004
" The main breakpoint has a zero subid.
func! s:Breakpoint2SignNumber(id, subid)
  return s:break_id + a:id * 1000 + a:subid
endfunction

func! s:Highlight(init, old, new)
  let default = a:init ? 'default ' : ''
  if a:new ==# 'light' && a:old !=# 'light'
    exe "hi " . default . "debugPC term=reverse ctermbg=lightblue guibg=lightblue"
  elseif a:new ==# 'dark' && a:old !=# 'dark'
    exe "hi " . default . "debugPC term=reverse ctermbg=darkblue guibg=darkblue"
  endif
  hi default debugBreakpoint term=reverse ctermbg=red guibg=red
  hi default debugBreakpointPending term=reverse ctermbg=yellow ctermfg=red guibg=yellow guifg=red
endfunc

call s:Highlight(1, '', &background)
au ColorScheme * call s:Highlight(1, '', &background)

func! s:StartDebug(bang, ...)
  " First argument is the command to debug, second core file or process ID.
  call s:Debug('+StartDebug')
  call s:StartDebug_internal({'gdb_args': a:000, 'bang': a:bang})
endfunc

func! s:StartDebugCommand(bang, ...)
  " First argument is the command to debug, rest are run arguments.
  call s:StartDebug_internal({'gdb_args': [a:1], 'proc_args': a:000[1:], 'bang': a:bang})
endfunc

func! s:StartDebug_internal(dict)
  if exists('s:gdbwin')
    echoerr 'Terminal debugger already running, cannot run two'
    return
  endif
  if !executable(g:termdebugger)
    echoerr 'Cannot execute debugger program "' .. g:termdebugger .. '"'
    return
  endif

  let s:ptywin = 0
  let s:pid = 0
  let s:asmwin = 0

  let s:pending_breakpoint_files = {}
  let s:pending_breakpoint_dlls = {}

  if exists('#User#TermdebugStartPre')
    doauto <nomodeline> User TermdebugStartPre
  endif

  " Uncomment this line to write logging in "debuglog".
  " call ch_logfile('debuglog', 'w')

  let s:sourcewin = win_getid(winnr())

  " Remember the old value of 'signcolumn' for each buffer that it's set in, so
  " that we can restore the value for all buffers.
  let b:save_signcolumn = &signcolumn
  let s:signcolumn_buflist = [bufnr()]

  let s:save_columns = 0
  let s:allleft = 0
  if exists('g:termdebug_wide')
    if &columns < g:termdebug_wide
      let s:save_columns = &columns
      let &columns = g:termdebug_wide
      " If we make the Vim window wider, use the whole left halve for the debug
      " windows.
      let s:allleft = 1
    endif
    let s:vertical = 1
  else
    let s:vertical = 0
  endif

  " Override using a terminal window by setting g:termdebug_use_prompt to 1.
  let use_prompt = exists('g:termdebug_use_prompt') && g:termdebug_use_prompt
  if (has('nvim') || has('terminal')) && !has('win32') && !use_prompt
    let s:way = 'terminal'
  else
    let s:way = 'prompt'
  endif

  call s:Debug('starting using '.s:way)
  if s:way == 'prompt'
    call s:StartDebug_prompt(a:dict)
  else
    call s:StartDebug_term(a:dict)
  endif

  if exists('g:termdebug_disasm_window')
    if g:termdebug_disasm_window
      let curwinid = win_getid(winnr())
      call s:GotoAsmwinOrCreateIt()
      call win_gotoid(curwinid)
    endif
  endif

  if exists('#User#TermdebugStartPost')
    doauto <nomodeline> User TermdebugStartPost
  endif
endfunc

func! s:CloseBuffers()
  if exists('s:ptyjob')
    call s:WipeJobBuffer(s:ptyjob)
  endif
  call s:WipeJobBuffer(s:commjob)
  call s:WipeJobBuffer(s:gdbjob)
  if s:stackbuf > 0
    exe 'bwipe! ' . s:stackbuf
  endif
  unlet! s:gdbwin
endfunc

func! s:UseSeparateTTYForProgram()
  return !exists('g:termdebug_separate_tty') || g:termdebug_separate_tty
endfunc

function! s:TermSendKeys(job, str)
  if has('nvim')
    call chansend(a:job['jobid'], a:str)
  else
    call term_sendkeys(a:job['buffer'], a:str)
  endif
endfunction

function! s:DispatchToOutFcn(FuncRefObj, chan_id, msgs, name)
  call a:FuncRefObj(a:chan_id, ''.join(a:msgs))
endfunction

function! s:DoNothing(...)
endfunction

" s:TermStart: nvim/vim compatible version for starting a new terminal
" Description: 
function! s:TermStart(cmd, opts)
  let term_name = get(a:opts, 'term_name', '')
  let vertical = get(a:opts, 'vertical', v:false)

  " Stupid f*ing vim rules: funcref objects can only be stored in variables
  " whose names start with capital letters!
  let OutCB = get(a:opts, 'out_cb', function('s:DoNothing'))
  let ExitCB = get(a:opts, 'exit_cb', function('s:DoNothing'))

  let hidden = get(a:opts, 'hidden', v:false)
  let term_finish = get(a:opts, 'term_finish', 'open')

  if has('nvim')
    if type(a:cmd) == v:t_string && a:cmd == 'NONE'
      let cmd = 'tail -f /dev/null;#'.term_name
    else
      let cmd = a:cmd
    endif

    if hidden
      let jobid = jobstart(cmd, {
	    \ 'on_stdout': function('s:DispatchToOutFcn', [OutCB]),
	    \ 'on_exit': ExitCB,
	    \ 'pty': v:true,
	    \ })
    else
      execute vertical ? 'vnew' : 'new'
      let jobid = termopen(cmd, {
	    \ 'on_stdout': function('s:DispatchToOutFcn', [OutCB]),
	    \ 'on_exit': ExitCB,
	    \ })
    endif
    if jobid <= 0
      return {}
    endif

    let pty_job_info = nvim_get_chan_info(jobid)
    let pty = pty_job_info['pty']
    let ptybuf = get(pty_job_info, 'buffer', -1)
  else
    let in_io = hidden ? 'null' : 'pipe'
    let ptybuf = term_start(a:cmd, {
	  \ 'term_name': term_name,
	  \ 'vertical': vertical,
	  \ 'out_cb': OutCB,
	  \ 'in_io': in_io,
	  \ 'exit_cb': ExitCB,
	  \ 'hidden': hidden,
	  \ 'term_finish': term_finish
	  \ })
    if ptybuf == 0
      return {}
    endif

    let job = term_getjob(ptybuf)
    let pty = job_info(job)['tty_out']
    let jobid = -1
    call setbufvar(ptybuf, '&buflisted', 0)
  endif
  return {
	\ 'buffer': ptybuf,
	\ 'pty': pty,
	\ 'jobid': jobid
	\ }
endfunction

func! s:StartDebug_term(dict)
  let usetty = s:UseSeparateTTYForProgram()
  let pty = ''
  if usetty
    " Open a terminal window without a job, to run the debugged program in.
    let s:ptyjob = s:TermStart('NONE', {
	  \ 'term_name': 'debugged program', 
	  \ 'vertical': s:vertical
	  \ })
    if empty(s:ptyjob)
      echoerr 'invalid argument (or job table is full) while opening terminal window'
      return
    endif
  endif
  if s:vertical
    " Assuming the source code window will get a signcolumn, use two more
    " columns for that, thus one less for the terminal window.
    exe (&columns / 2 - 1) . "wincmd |"
    if s:allleft
      " use the whole left column
      wincmd H
    endif
  endif

  " Create a hidden terminal window to communicate with gdb
  let s:commjob = s:TermStart('NONE', {
	\ 'term_name': 'gdb communication',
	\ 'out_cb': function('s:CommOutput'),
	\ 'hidden': 1
	\ })
  if empty(s:commjob)
    echoerr 'Failed to open the communication terminal window'
    exe 'bwipe! ' . s:ptyjob['buffer']
    return
  endif
  " Open a terminal window to run the debugger.
  " Add -quiet to avoid the intro message causing a hit-enter prompt.
  let gdb_args = get(a:dict, 'gdb_args', [])

  if exists('*TermDebugGdbCmd')
    let cmd = TermDebugGdbCmd(pty)
  elseif usetty
    let cmd = [g:termdebugger, '-quiet', '-tty', pty] + gdb_args
  else
    let cmd = [g:termdebugger, '-quiet'] + gdb_args
  endif

  " call ch_log('executing "' . join(cmd) . '"')
  let s:foundGdbPrompt = 0
  let s:gdbjob = s:TermStart(cmd, {
	\ 'term_name': 'GDB',
	\ 'term_finish': 'close',
	\ 'out_cb': function('s:OnGdbMainOutput', [a:dict]),
	\ 'exit_cb': function('s:EndTermDebug')
	\ })
  let s:gdbwin = win_getid(winnr())
  if empty(s:gdbjob)
    echoerr 'Failed to open the gdb terminal window'
    call s:CloseBuffers()
    return
  endif
endfunc

func! s:MakeGDBCommandLineVisibleAndInTerminalMode(msg)
    let curwinid = win_getid(winnr())
    call win_gotoid(s:gdbwin)
    let gdbwinmode= mode()
    if gdbwinmode != 't'
        normal! GA
    endif
    call win_gotoid(curwinid)
endfunc

func! s:OnGdbMainOutput(dict, chan, msg)
  if s:foundGdbPrompt
      if a:msg =~ '(gdb)'
          " GDB command is finished executing.
          call s:MakeGDBCommandLineVisibleAndInTerminalMode(a:msg)
      endif
      return
  endif

  " Sometimes we might get a bunch of hit-enter prompts even before we get
  " a chance to turn off pagination. This can happen for instance if the
  " .gdbinit prints out a lot of messages and the Vim window is
  " sufficiently small.
  if a:msg =~ '--Type <RET> for more, q to quit, c to continue without paging--'
    call s:TermSendKeys(s:gdbjob, "c\r")
  elseif a:msg =~ '(gdb)'
    let s:foundGdbPrompt = 1
    call s:StartDebug_term_step2(a:dict)
  endif
endfunc

func! s:HasGdbProcessExited()
  if has('nvim')
    return nvim_get_chan_info(s:gdbjob['jobid']) == {}
  else
    let gdbproc = term_getjob(s:gdbjob['buffer'])
    return gdbproc == v:null || job_status(gdbproc) !=# 'run'
  endif
endfunc

func! s:TermGetLine(job, lnum)
  let bufid = a:job['buffer']
  if has('nvim')
    return get(getbufline(bufid, a:lnum), 0, '')
  else
    return term_getline(bufid, a:lnum)
  endif
endfunction

func! s:StartDebug_term_step2(dict)
  " Connect gdb to the communication pty, using the GDB/MI interface
  call s:Debug('getting to s:StartDebug_term_step2')

  " Set arguments to be run
  let proc_args = get(a:dict, 'proc_args', [])
  if len(proc_args)
    call s:TermSendKeys(s:gdbjob, 'set args ' . join(proc_args) . "\r")
  endif

  call s:TermSendKeys(s:gdbjob, 'new-ui mi ' . s:commjob['pty'] . "\r")

  " Wait for the response to show up, users may not notice the error and wonder
  " why the debugger doesn't work.
  let try_count = 0
  while 1
    if s:HasGdbProcessExited()
      echoerr string(g:termdebugger) . ' exited unexpectedly'
      call s:CloseBuffers()
      return
    endif

    let response = ''
    for lnum in range(1,200)
      let line1 = s:TermGetLine(s:gdbjob, lnum)
      let line2 = s:TermGetLine(s:gdbjob, lnum + 1)
      if line1 =~ 'new-ui mi '
	" response can be in the same line or the next line
	let response = line1 . line2
	if response =~ 'Undefined command'
	  echoerr 'Sorry, your gdb is too old, gdb 7.12 is required'
	  call s:CloseBuffers()
	  return
	endif
	if response =~ 'New UI allocated'
	  " Success!
	  break
	endif
      elseif line1 =~ 'Reading symbols from' && line2 !~ 'new-ui mi '
	" Reading symbols might take a while, try more times
	let try_count -= 1
      endif
    endfor
    if response =~ 'New UI allocated'
      break
    endif
    let try_count += 1
    call s:Debug('try_count = '.try_count)
    if try_count > 100
      echoerr 'Cannot check if your gdb works, continuing anyway'
      break
    endif
    sleep 10m
  endwhile

  " Interpret commands while the target is running.  This should usually only be
  " exec-interrupt, since many commands don't work properly while the target is
  " running.
  call s:SendCommand('-gdb-set mi-async on')
  " Older gdb uses a different command.
  call s:SendCommand('-gdb-set target-async on')

  " Disable pagination, it causes everything to stop at the gdb
  " "Type <return> to continue" prompt.
  call s:SendCommand('set pagination off')

  call s:StartDebugCommon(a:dict)
endfunc

func! s:StartDebug_prompt(dict)
  " Open a window with a prompt buffer to run gdb in.
  if s:vertical
    vertical new
  else
    new
  endif
  let s:gdbwin = win_getid(winnr())
  let s:promptbuf = bufnr('')
  call prompt_setprompt(s:promptbuf, 'gdb> ')
  set buftype=prompt
  file gdb
  call prompt_setcallback(s:promptbuf, function('s:PromptCallback'))
  call prompt_setinterrupt(s:promptbuf, function('s:PromptInterrupt'))

  if s:vertical
    " Assuming the source code window will get a signcolumn, use two more
    " columns for that, thus one less for the terminal window.
    exe (&columns / 2 - 1) . "wincmd |"
  endif

  " Add -quiet to avoid the intro message causing a hit-enter prompt.
  let gdb_args = get(a:dict, 'gdb_args', [])
  let proc_args = get(a:dict, 'proc_args', [])

  let cmd = [g:termdebugger, '-quiet', '--interpreter=mi2'] + gdb_args
  " call ch_log('executing "' . join(cmd) . '"')

  let s:gdbjob = job_start(cmd, {
	\ 'exit_cb': function('s:EndPromptDebug'),
	\ 'out_cb': function('s:GdbOutCallback'),
	\ })
  if job_status(s:gdbjob) != "run"
    echoerr 'Failed to start gdb'
    exe 'bwipe! ' . s:promptbuf
    return
  endif
  " Mark the buffer modified so that it's not easy to close.
  set modified
  let s:gdb_channel = job_getchannel(s:gdbjob)  

  " Interpret commands while the target is running.  This should usually only
  " be exec-interrupt, since many commands don't work properly while the
  " target is running.
  call s:SendCommand('-gdb-set mi-async on')
  " Older gdb uses a different command.
  call s:SendCommand('-gdb-set target-async on')

  let s:ptybuf = 0
  if has('win32')
    " MS-Windows: run in a new console window for maximum compatibility
    call s:SendCommand('set new-console on')
  elseif has('terminal') && s:UseSeparateTTYForProgram()
    " Unix: Run the debugged program in a terminal window.  Open it below the
    " gdb window.
    belowright let s:ptybuf = term_start('NONE', {
	  \ 'term_name': 'debugged program',
	  \ })
    if s:ptybuf == 0
      echoerr 'Failed to open the program terminal window'
      call job_stop(s:gdbjob)
      return
    endif
    let s:ptywin = win_getid(winnr())
    let pty = job_info(term_getjob(s:ptybuf))['tty_out']
    call s:SendCommand('tty ' . pty)

    " Since GDB runs in a prompt window, the environment has not been set to
    " match a terminal window, need to do that now.
    call s:SendCommand('set env TERM = xterm-color')
    call s:SendCommand('set env ROWS = ' . winheight(s:ptywin))
    call s:SendCommand('set env LINES = ' . winheight(s:ptywin))
    call s:SendCommand('set env COLUMNS = ' . winwidth(s:ptywin))
    call s:SendCommand('set env COLORS = ' . &t_Co)
    call s:SendCommand('set env VIM_TERMINAL = ' . v:version)
  else
    " TODO: open a new terminal get get the tty name, pass on to gdb
    call s:SendCommand('show inferior-tty')
  endif
  call s:SendCommand('set print pretty on')
  call s:SendCommand('set breakpoint pending on')
  " Disable pagination, it causes everything to stop at the gdb
  call s:SendCommand('set pagination off')

  " Set arguments to be run
  if len(proc_args)
    call s:SendCommand('set args ' . join(proc_args))
  endif

  call s:StartDebugCommon(a:dict)

  if has('nvim')
    " nvim starts terminal in 'normal' mode. just doing startinsert does
    " not work unless we also navigate to the last line of the buffer!
    normal! Ga
  endif
endfunc

func! s:StartDebugCommon(dict)
  " Sign used to highlight the line where the program has stopped.
  " There can be only one.
  sign define debugPC linehl=debugPC
  hi debugPC cterm=reverse gui=reverse

  " Install debugger commands in the text window.
  call win_gotoid(s:sourcewin)
  call s:InstallCommands()
  call win_gotoid(s:gdbwin)

  " Enable showing a balloon with eval info
  if has("balloon_eval") || has("balloon_eval_term")
    set balloonexpr=
    "ppatil: temporarily commenting out hover-over as it crashes GDB.
    set balloonexpr=TermDebugBalloonExpr()
    if has("balloon_eval")
      set ballooneval
    endif
    if has("balloon_eval_term")
      set balloonevalterm
    endif
  endif

  tnoremap <ScrollWheelUp> <C-W>N<ScrollWheelUp>

  if exists('g:termdebug_persist_breakpoints') && g:termdebug_persist_breakpoints
    call s:RestoreBreakpoints()
  else
    " Contains breakpoints that have been placed, key is a string with the GDB
    " breakpoint number.
    " Each entry is a dict, containing the sub-breakpoints.  Key is the subid.
    " For a breakpoint that is just a number the subid is zero.
    " For a breakpoint "123.4" the id is "123" and subid is "4".
    " Example, when breakpoint "44", "123", "123.1" and "123.2" exist:
    " {'44': {'0': entry}, '123': {'0': entry, '1': entry, '2': entry}}
    let s:breakpoints = {}
  endif

  let s:stackbuf = -1

  augroup TermDebug
    au BufRead * call s:BufRead()
    au BufUnload * call s:BufUnloaded()
    au OptionSet background call s:Highlight(0, v:option_old, v:option_new)
  augroup END

  " Run the command if the bang attribute was given and got to the debug
  " window.
  if get(a:dict, 'bang', 0)
    call s:SendCommand('-exec-run')
    call win_gotoid(s:ptywin)
  endif

  call s:Debug('broadcasting TermDebugStarted')
  doautocmd User TermDebugStarted

  let s:gdb_started = 1
  if has('nvim')
    normal! Ga
  endif
endfunc
" Send a command to gdb.  "cmd" is the string without line terminator.
func! s:SendCommand(cmd)
  " call ch_log('sending to gdb: ' . a:cmd)
  if s:way == 'prompt'
    call ch_sendraw(s:gdb_channel, a:cmd . "\n")
  else
    call s:TermSendKeys(s:commjob, a:cmd . "\r")
  endif
endfunc

" This is global so that a user can create their mappings with this.
" Note: If the program is running when this command is called, it
" interrupts the program
func! TermDebugSendCommand(cmd)
  if s:way == 'prompt'
    call ch_sendraw(s:gdb_channel, a:cmd . "\n")
  else
    call s:InterruptInferior()
    call s:TermSendKeys(s:gdbjob, a:cmd . "\r")
  endif
endfunc

" Function called when entering a line in the prompt buffer.
func! s:PromptCallback(text)
  call s:SendCommand(a:text)
endfunc

" Function called when pressing CTRL-C in the prompt buffer and when placing a
" breakpoint.
func! s:PromptInterrupt()
  " call ch_log('Interrupting gdb')
  if has('win32')
    " Using job_stop() does not work on MS-Windows, need to send SIGTRAP to
    " the debugger program so that gdb responds again.
    if s:pid == 0
      echoerr 'Cannot interrupt gdb, did not find a process ID'
    else
      call debugbreak(s:pid)
    endif
  else
    call job_stop(s:gdbjob, 'int')
  endif
endfunc

" Function called when gdb outputs text.
func! s:GdbOutCallback(channel, text)
  " call ch_log('received from gdb: ' . a:text)

  " Drop the gdb prompt, we have our own.
  " Drop status and echo'd commands.
  if a:text == '(gdb) ' || a:text == '^done' || a:text[0] == '&'
    return
  endif
  if a:text =~ '^^error,msg='
    let text = s:DecodeMessage(a:text[11:])
    if exists('s:evalexpr') && text =~ 'A syntax error in expression, near\|No symbol .* in current context'
      " Silently drop evaluation errors.
      unlet s:evalexpr
      return
    endif
  elseif a:text[0] == '~'
    let text = s:DecodeMessage(a:text[1:])
  else
    call s:CommOutput(a:channel, a:text)
    return
  endif

  let curwinid = win_getid(winnr())
  call win_gotoid(s:gdbwin)

  " Add the output above the current prompt.
  call append(line('$') - 1, text)
  set modified

  call win_gotoid(curwinid)
endfunc

" Decode a message from gdb.  quotedText starts with a ", return the text up
" to the next ", unescaping characters.
func! s:DecodeMessage(quotedText)
  if a:quotedText[0] != '"'
    echoerr 'DecodeMessage(): missing quote in ' . a:quotedText
    return
  endif
  let result = ''
  let i = 1
  while a:quotedText[i] != '"' && i < len(a:quotedText)
    if a:quotedText[i] == '\'
      let i += 1
      if a:quotedText[i] == 'n'
	" drop \n
	let i += 1
	continue
      elseif a:quotedText[i] == 't'
	" append \t
	let i += 1
	let result .= "\t"
	continue
      endif
    endif
    let result .= a:quotedText[i]
    let i += 1
  endwhile
  return result
endfunc

" Extract the "name" value from a gdb message with fullname="name".
func! s:GetFullname(msg)
  if a:msg !~ 'fullname'
    return ''
  endif
  let name = s:DecodeMessage(substitute(a:msg, '.*fullname=', '', ''))
  if has('win32') && name =~ ':\\\\'
    " sometimes the name arrives double-escaped
    let name = substitute(name, '\\\\', '\\', 'g')
  endif
  return name
endfunc

func! s:WipeJobBuffer(job)
  if !empty(a:job) && a:job['buffer'] > 0
    exe 'bwipe! '.a:job['buffer']
  endif
endfunc

func! s:EndTermDebug(...)
  call s:CloseBuffers()
  call s:EndDebugCommon()
endfunc

func! s:EndDebugCommon()
  let curwinid = win_getid(winnr())

  " Restore 'signcolumn' in all buffers for which it was set.
  call win_gotoid(s:sourcewin)
  let was_buf = bufnr()
  for bufnr in s:signcolumn_buflist
    if bufexists(bufnr)
      exe bufnr .. "buf"
      if exists('b:save_signcolumn')
	let &signcolumn = b:save_signcolumn
	unlet b:save_signcolumn
      endif
    endif
  endfor
  exe was_buf .. "buf"

  call s:DeleteCommands()

  call win_gotoid(curwinid)

  if s:save_columns > 0
    let &columns = s:save_columns
  endif

  if has("balloon_eval") || has("balloon_eval_term")
    set balloonexpr=
    if has("balloon_eval")
      set noballooneval
    endif
    if has("balloon_eval_term")
      set noballoonevalterm
    endif
  endif

  doautocmd User TermDebugStopped
  au! TermDebug

  let s:gdb_started = 0

  let bps = s:GetSignLocations('TermDebugBreakpoints')
  call s:ClearBreakpointInfo()
  for bp in bps
    call sign_place(0, 
	  \ 'TermDebugPendingBreakpoints', 'debugBreakpointPending', bp['fname'], {
	    \ 'lnum': bp['lnum'],
	    \ })
  endfor
  call sign_unplace('TermDebugBreakpoints')
endfunc

func! s:EndPromptDebug(job, status)
  let curwinid = win_getid(winnr())
  call win_gotoid(s:gdbwin)
  set nomodified
  close
  if curwinid != s:gdbwin
    call win_gotoid(curwinid)
  endif

  call s:EndDebugCommon()
  unlet s:gdbwin
endfunc

func! TermDebugPrintHelper(isVisual)
    if a:isVisual
	let varName = @"
    else
	let varName = expand('<cword>')
    endif
    if s:current_frame_type == "M"
        let pmlCmd = "printf \"%s\", SF::EvaluateCmdAtMATLABStackLevel(".s:current_frame_idx.",\"".varName."\")"."\r"
        call s:TermSendKeys(s:gdbjob, pmlCmd)
    else
        call TermDebugSendCommand("print ".varName)
    endif
endfunction

func! s:LoadSharedLibraryContainingFile(filePath)
    if has_key(s:pending_breakpoint_files, a:filePath)
	return
    endif
    let s:pending_breakpoint_files[a:filePath] = 1

    let sbRootDir = mw#utils#GetRootDir()
    let fullFilePath = sbRootDir.'/matlab/'.a:filePath
    let fullFileDir = fnamemodify(fullFilePath, ':p:h')
    let makeFilePath = findfile('Makefile', fullFileDir.';')
    if makeFilePath == ''
	return
    endif

    let makeFileTxt = readfile(makeFilePath)
    let matches = matchlist(makeFileTxt, 'MODNAME\s*:=\s*\(\w\+\)')
    if !empty(matches)
	let modname = matches[1]
    else
	let modname = fnamemodify(makeFilePath, ':p:h:t')
    endif
    if !empty(matchstr(makeFileTxt, 'MOD_TYPE\s*:=\s*Mex'))
	let dllname = modname.'.mex'
    else
	let dllname = 'libmw'.modname.'.so'
    endif
    if has_key(s:pending_breakpoint_dlls, dllname)
	return
    endif
    let s:pending_breakpoint_dlls[dllname] = 1
    call s:SendCommand('sb-auto-load-libs '.dllname)
    echo 'GDB finished loading debug symbols for '.dllname.'. Breakpoint turns red when and if MATLAB loads '.dllname.'.'
endfunc

" Handle a message received from gdb on the GDB/MI interface.
func! s:CommOutput(chan, msg)
  let msgs = split(a:msg, "\r", v:true)
  " This rigamarole with pendingOutput is to account for truncated lines.
  " We occassionally get a single GDB message split across multiple calls
  " to on_stdout. Therefore, keep pending messages around untile we get a
  " "\r" which indicates a message is complete.
  let msgs[0] = s:pendingOutput . msgs[0]
  let s:pendingOutput = msgs[-1]
  let pendingBreakpointInfoOutputPatternString = "breakpoint     keep y   <PENDING>  "

  " Do not process the last line of the message (hence the 0:-2). This
  " prevents us from processing incomplete lines.
  for msg in msgs[0:-2]

    let msg = trim(msg)
    if msg == ''
      continue
    endif
    " WISH: Just pass how we are calling HandleCursor instead of repeating
    " regexps in HandleCursor
    if msg =~ '^\(\*stopped\|\*running\)'
        if msg =~ '^\*stopped' && s:gdbstatus == 'InferiorRunning'
          let s:gdbstatus = 'InferiorStopped'
        endif
      call s:HandleCursor(msg)
    elseif msg =~ '^\(=thread-selected\|\^done,frame=\)'
      call s:HandleCFrameOrStoppedMsg(msg)
    elseif msg =~ '\^done,bkpt=' || msg =~ '=breakpoint-created,'
      call s:HandleBreakpointCreated(msg)
    elseif msg =~ '^\^done,BreakpointTable='
      call s:HandleBreakpointInfo(msg)
    elseif msg =~ '^=breakpoint-deleted,'
      call s:HandleBreakpointDeleted(msg)
    elseif msg =~ '^=breakpoint-modified,'
      call s:HandleBreakpointModified(msg)
    elseif msg =~ '^\^done,stack='
      let s:current_stack_type = 'c'
      call s:HandleCStackInfo(msg)
    elseif msg =~ '^=thread-group-added'
      let s:gdbstatus='GdbStarted'
    elseif msg =~ '^=thread-group-started'
      let s:gdbstatus='InferiorAttached'
      call s:UpdateMLBreakpoint(v:true)
      "does s:SendCommand work or needed here?
      call s:SendCommand('info b')
      call s:HandleProgramRun(msg)
    elseif msg =~ '^=thread-group-exited' 
      let s:gdbstatus='InferiorExited'
      call s:UpdateMLBreakpoint(v:false)
    elseif msg =~ '^\^done,value=' || msg =~ s:evalexpr.' =' || msg =~ 'ans ='
      call s:HandleEvaluate(msg)
    elseif msg =~ '^\^error,msg='
      call s:HandleError(msg)
    elseif msg =~ '--start--stack--'
      let s:collecting_hybrid_stack = 1
      let s:hybrid_stack = ""
    elseif msg =~ '^\~"--end--stack--'
      if s:collecting_hybrid_stack == 1
	let s:current_stack_type = matchstr(msg, '--end--stack--\zs.')
	let s:collecting_hybrid_stack = 0
	call s:HandleMOrHybridStackInfo()
      endif
    elseif msg =~ '^\^running'
        let oldGdbstatus = s:gdbstatus
        let s:gdbstatus = 'InferiorRunning'
        if oldGdbstatus == 'InferiorAttached'
            call s:UpdateMLBreakpoint(v:true)
        endif
    elseif stridx(msg, pendingBreakpointInfoOutputPatternString) > 0
      " breakpoint is pending, load sharedlibrary
      " example command: info b $bpNum
      " example msg    : 17     breakpoint     keep y   <PENDING> matlab/toolbox/stateflow/src/stateflow/cdr/cdr_eml_construct.cpp:682\n
      if s:gdbstatus == 'InferiorAttached' || s:gdbstatus == 'InferiorRunning' || s:gdbstatus == 'InferiorStopped'
	let s:filePath = msg[stridx(msg, pendingBreakpointInfoOutputPatternString) + len(pendingBreakpointInfoOutputPatternString):stridx(msg, ":") - 1]       
	call s:LoadSharedLibraryContainingFile(s:filePath)
      endif
    elseif s:collecting_hybrid_stack
      if msg =~ '^\~"\s*#'
	let s:hybrid_stack .= msg[2:-2]
      endif
    endif
  endfor
endfunc

func! s:GotoProgram()
  if has('win32')
    if executable('powershell')
      call system(printf('powershell -Command "add-type -AssemblyName microsoft.VisualBasic;[Microsoft.VisualBasic.Interaction]::AppActivate(%d);"', s:pid))
    endif
  else
    call win_gotoid(s:ptywin)
  endif
endfunc
func! s:GDBDebuggerCommandWrapperForTerm(cDebugCommand, mDebugCommand)
    if s:stoppedInMATLAB == v:true
        let s:stoppedInMATLAB = v:false
        call s:SendCommand(a:mDebugCommand)
    else
        call TermDebugSendCommand(a:cDebugCommand)
    end
endfunc
func! s:GDBDebuggerCommandWrapper(cDebugCommand, mDebugCommand)
    if s:stoppedInMATLAB == v:true
        let s:stoppedInMATLAB = v:false
        call s:SendCommand(a:mDebugCommand)
    else
        call s:SendCommand(a:cDebugCommand)
    end
endfunc
func! s:StepWrapper()
    call s:GDBDebuggerCommandWrapper('-exec-step','dbstepin')
endfunc

func! s:OverWrapper()
    call s:GDBDebuggerCommandWrapper('-exec-next','dbstep')
endfunc

func! s:FinishWrapper()
    call s:GDBDebuggerCommandWrapper('-exec-finish','dbstepout')
endfunc

func! s:ContinueWrapper()
    if s:way == 'prompt'
        call s:GDBDebuggerCommandWrapper('-exec-continue','dbcont')
    else
        call s:GDBDebuggerCommandWrapperForTerm('continue','dbcont')
    endif
endfunc

" Install commands in the current window to control the debugger.
func! s:InstallCommands()
  call s:Debug("Installing commands")
  let save_cpo = &cpo
  set cpo&vim

  command! -nargs=? Break call s:SetBreakpoint(<q-args>)
  command! -nargs=? Until call s:Until(<q-args>)
  command! -nargs=? Jump call s:Jump(<q-args>)
  command! Clear call s:ClearBreakpoint()
  command! Step call s:StepWrapper()
  command! Over call s:OverWrapper()
  command! Finish call s:FinishWrapper()
  " Use finish so that GDB displays the helpful return value
  command! -nargs=* Run call s:Run(<q-args>)
  command! -nargs=* Arguments call s:SendCommand('-exec-arguments ' . <q-args>)
  command! Stop call s:SendCommand('-exec-interrupt')
  command! -nargs=* GDB call TermDebugSendCommand(<q-args>)
  command! StackM call s:ShowMStack()
  command! StackH call s:ShowHybridStack()
  command! Stack call s:ShowCStack()
  command! -nargs=? LoadAndShowStack :call s:LoadAndShowStackImpl(<q-args>)

  " using -exec-continue results in CTRL-C in gdb window not working
  command! Continue call s:ContinueWrapper()

  command! -range -nargs=* Evaluate call s:Evaluate(<range>, <q-args>)
  command! ShowGdb call s:ShowGdb()
  command! ShowProgram call win_gotoid(s:ptywin)
  command! Source call s:GotoSourcewinOrCreateIt()
  command! Winbar call s:InstallWinbar()

  nnoremap K :Evaluate<CR>

  if has('menu') && &mouse != ''
    if !exists('g:termdebug_install_winbar') || g:termdebug_install_winbar
      call s:InstallWinbar()
    endif

    if !exists('g:termdebug_popup') || g:termdebug_popup != 0
      let s:saved_mousemodel = &mousemodel
      let &mousemodel = 'popup_setpos'
      an 1.200 PopUp.-SEP3-	<Nop>
      an 1.210 PopUp.Set\ breakpoint	:Break<CR>
      an 1.220 PopUp.Clear\ breakpoint	:Clear<CR>
      an 1.230 PopUp.Evaluate		:Evaluate<CR>
    endif
  endif

  let &cpo = save_cpo
endfunc

function! s:ShowGdb()
  if !win_gotoid(s:gdbwin)
    if s:vertical
      exec 'vert sb '.s:gdbjob['buffer']
    else
      exec 'sb '.s:gdbjob['buffer']
    endif
    let s:gdbwin = win_getid(winnr())
  endif
endfunc

" Install the window toolbar in the current window.
func! s:InstallWinbar()
  if has('menu') && &mouse != ''
    nnoremenu WinBar.Step   :Step<CR>
    nnoremenu WinBar.Next   :Over<CR>
    nnoremenu WinBar.Finish :Finish<CR>
    nnoremenu WinBar.Cont   :Continue<CR>
    nnoremenu WinBar.Stop   :Stop<CR>
    nnoremenu WinBar.Eval   :Evaluate<CR>
    call add(s:winbar_winids, win_getid(winnr()))
  endif
endfunc

func! s:ClearBreakpointInfo()
  for [id, entries] in items(s:breakpoints)
    for subid in keys(entries)
      call s:UnplaceBreakpointSign(id, subid)
    endfor
  endfor
  let s:breakpoints = {}

  for val in keys(s:breakpoint_signs)
    exe "sign undefine ".val
  endfor
  let s:breakpoint_signs = {}
endfunc

" Delete installed debugger commands in the current window.
func! s:DeleteCommands()
  delcommand Break
  delcommand Clear
  delcommand Step
  delcommand Over
  delcommand Finish
  delcommand Run
  delcommand Arguments
  delcommand Stop
  delcommand Continue
  delcommand Evaluate
  delcommand ShowGdb
  delcommand GDB
  delcommand ShowProgram
  delcommand Source
  delcommand Winbar
  delcommand Stack

  nunmap K

  if has('menu')
    " Remove the WinBar entries from all windows where it was added.
    let curwinid = win_getid(winnr())
    for winid in s:winbar_winids
      if win_gotoid(winid)
	aunmenu WinBar.Step
	aunmenu WinBar.Next
	aunmenu WinBar.Finish
	aunmenu WinBar.Cont
	aunmenu WinBar.Stop
	aunmenu WinBar.Eval
      endif
    endfor
    call win_gotoid(curwinid)
    let s:winbar_winids = []

    if exists('s:saved_mousemodel')
      let &mousemodel = s:saved_mousemodel
      unlet s:saved_mousemodel
      aunmenu PopUp.-SEP3-
      aunmenu PopUp.Set\ breakpoint
      aunmenu PopUp.Clear\ breakpoint
      aunmenu PopUp.Evaluate
    endif
  endif

  exe 'sign unplace ' . s:pc_id
  sign undefine debugPC
endfunc

func! s:InterruptInferior()
  if !s:stopped
    let do_continue = 1
    if s:way == 'prompt'
      call s:PromptInterrupt()
    else
      call s:SendCommand('-exec-interrupt')
    endif
    sleep 10m
  endif
endfunc

func! s:LocationCmd(at, cmd)
  if !empty(a:at)
    let at = a:at
  elseif exists('*TermdebugFilenameModifier')
    let at = TermdebugFilenameModifier(expand('%:p')) . ':' . line('.')
  else
    " Use the fname:lnum format, older gdb can't handle --source.
    let at = fnameescape(expand('%:p')) . ':' . line('.')
  endif

  call s:SendCommand(a:cmd.' '.at)
endfunc

" :Break - Set a breakpoint at the cursor position.
func! s:SetBreakpoint(at)
  " Use break instead of -break-insert. -break-insert does not seem to
  " honor "set breakpoint pending on" option.
  call s:LocationCmd(a:at, 'break')
  call s:SendCommand('info b $bpnum') "to load sharedlibrary of breakpoint location if pending
endfunc

func! s:UnplaceBreakpointSign(id, subid)
  exe 'sign unplace ' . s:Breakpoint2SignNumber(a:id, a:subid).' group=TermDebugBreakpoints'
endfunc

" :Clear - Delete a breakpoint at the cursor position.
func! s:ClearBreakpoint()
  let info = sign_getplaced(bufname(), {'group': 'TermDebugBreakpoints', 'lnum': line('.')})
  if empty(info[0]['signs'])
    return
  endif

  for sign in info[0].signs
    let signId = sign['id']
    let id = signId / 1000
    exe 'sign unplace ' . signId . ' group=TermDebugBreakpoints'
    unlet s:breakpoints[id]
    call s:SendCommand('-break-delete '.id)
  endfor
endfunc
func! ResumeMATLAB(arg1)
    call TermDebugSendCommand('c')
endfunc
func! s:UpdateMLBreakpoint(resumeMATLAB)
    if empty(s:MLBreakpoints)
        return
    endif
    if a:resumeMATLAB && s:gdbstatus == 'InferiorAttached'
        let timer = timer_start(100,'ResumeMATLAB')
        return
    endif
    for bpKey in keys(s:MLBreakpoints)
        let bpInfo = split(bpKey,':')
        call s:ToggleMLBreakpoint(bpInfo[0], bpInfo[1])
        call s:ToggleMLBreakpoint(bpInfo[0], bpInfo[1])
    endfor
    if a:resumeMATLAB
        let timer = timer_start(100,'ResumeMATLAB')
    endif

endfunc

func! s:ToggleMLBreakpoint(fileName, lineNumber)
  if a:fileName !~ '\.m$'
      return;
  endif
  let breakpointId = a:fileName.':'.a:lineNumber
  let pendingMLBreakpoint = s:gdbstatus != 'InferiorRunning' && s:gdbstatus != 'InferiorStopped'
  let signName = 'MLBreakpoint'
  if pendingMLBreakpoint
      let signName = signName.'Pending'
  endif
  let currentSign = sign_getplaced(a:fileName, {'lnum': a:lineNumber})
  call sign_define('MLBreakpointPending', {'text':'M>', 'texthl':'debugBreakpointPending'})
  call sign_define('MLBreakpoint', {'text':'M>', 'texthl':'debugBreakpoint'})
  if empty(currentSign[0].signs)
      let MLBreakpointToggleCommand = "mleval \"SF4MLTest.Utils.ToggleMATLABBreakpoint('".a:fileName."','".a:lineNumber."',1)\""
      let signId = sign_place(0, '', signName, a:fileName, {'lnum': a:lineNumber})
      let s:MLBreakpoints[breakpointId] = signId
  else
      let MLBreakpointToggleCommand = "mleval \"SF4MLTest.Utils.ToggleMATLABBreakpoint('".a:fileName."','".a:lineNumber."',-1)\""
      call sign_unplace('', {'id': s:MLBreakpoints[breakpointId]})
      unlet s:MLBreakpoints[breakpointId] 
  endif
  if !pendingMLBreakpoint
      call TermDebugSendCommand(MLBreakpointToggleCommand)
  endif
endfunc

func! s:ToggleBreakpoint()
  if expand('%:p') =~ '\.m$'
    call s:ToggleMLBreakpoint(expand('%:p'),line('.'))
    return
  endif
  if s:gdb_started == 0
    call s:Debug('setting pending breakpoint')
    call s:TogglePendingBreakpoint()
    return
  endif

  let info = sign_getplaced(bufname(), {'group': 'TermDebugBreakpoints', 'lnum': line('.')})
  if empty(info[0]['signs'])
    call s:Debug('setting breakpoint')
    call s:SetBreakpoint('')
  else
    call s:Debug('clearing breakpoint')
    call s:ClearBreakpoint()
  endif
endfunc

command! ToggleBreakpoint call s:ToggleBreakpoint()

func! s:Until(at)
  call s:LocationCmd(a:at, 'until')
endfunc

func! s:Jump(at)
  call s:LocationCmd(a:at, 'tbreak')
  call s:LocationCmd(a:at, 'jump')
endfunc

function! s:LoadAndShowStackImpl(level)
    let ulevel = input('Stack depth to load 1/2/3/.../all :')
    echo "\nLoading symbols for current stack. It might take a while. Wait for stack window to update."
    call TermDebugSendCommand('sb-load-stack '.ulevel)
    call s:ShowCStack()
endfunction

" s:UpdateStackTypeStatusLine:  {{{
" Description: updates the statusline text of the stack window to indicate
" what is being shown. 
function! s:UpdateStackTypeStatusLine(winnum)
  if s:current_stack_type == 'm'
    let statusline = 'Stack [MATLAB]'
  elseif s:current_stack_type == 'h'
    let statusline = 'Stack [C + MATLAB (hybrid)]'
  else
    let statusline = 'Stack [C]'
  endif
  call setwinvar(a:winnum, '&statusline', statusline)
endfunction " }}}

func! s:ShowStackPre()
  let curwinid = win_getid()
  let stackbufname = "_GDB_Stack_Window_"
  if s:stackbuf == -1
      let s:stackbuf = bufnr(stackbufname, 1) 
      call setbufvar(s:stackbuf, '&swapfile', 0)
      call setbufvar(s:stackbuf, '&buflisted', 0)
      call setbufvar(s:stackbuf, '&buftype', 'nofile')
      call setbufvar(s:stackbuf, '&ts', 8)
  endif

  let winnum = bufwinid(s:stackbuf)
  
  if winnum != -1
    call win_gotoid(winnum)
    exec "silent! file ".stackbufname
  else
    if win_gotoid(s:gdbwin)
      exec 'vert sbuffer '.s:stackbuf
    else
      exec 'sbuffer '.s:stackbuf
    endif
  endif
  let winnum = bufwinid(s:stackbuf)
  call s:UpdateStackTypeStatusLine(winnum)
  setlocal nowrap
  nmap <buffer> <silent> <CR>           :call <SID>GotoSelectedFrame(line('.'))<CR>
  nmap <buffer> <silent> <2-LeftMouse>  :call <SID>GotoSelectedFrame(line('.'))<CR>
  return winnum
endfunc

" s:IssueGenericStackListCmd:  {{{
" Description: 
function! s:IssueGenericStackListCmd(gdbcmd, stacktype)
  call s:SendCommand('echo --start--stack--'.a:stacktype)
  call s:SendCommand(a:gdbcmd)
  call s:SendCommand('echo --end--stack--'.a:stacktype)
endfunction " }}}

" s:IssueHybridStackListCmd:  {{{
" Description: 
function! s:IssueHybridStackListCmd()
  echomsg "Loading hybrid stack. It might take a while. Wait for stack window to update."
  call TermDebugSendCommand('sb-load-stack 200')

  call s:Debug('issuing hybrid stack list cmd')
  call s:IssueGenericStackListCmd('hybrid_stack', 'h')
endfunction " }}}

func! s:ShowHybridStack()
  if !s:stopped
    echoerr "Interrupt GDB to show stack"
    return
  endif
  call s:IssueHybridStackListCmd()
  " Refresh the stack to show the current C++ frame.
  call s:SendCommand("-stack-info-frame")
endfunc

" s:IssueMStackListCmd:  {{{
" Description: 
function! s:IssueMStackListCmd()
  call s:IssueGenericStackListCmd('mstack', 'm')
endfunction " }}}

func! s:ShowMStack()
  if !s:stopped
    echoerr "Interrupt GDB to show stack"
    return
  endif
  call s:ShowStackPre()
  call s:IssueMStackListCmd()
endfunc

func! s:IssueCStackListCmd()
  " WISH: Convert this to the generic form of handling stacks as well.
  call s:SendCommand('-stack-list-frames 0 200')
endfunc

func! s:ShowCStack()
  if !s:stopped
    echoerr "Interrupt GDB to show stack"
    return
  endif
  call s:ShowStackPre()
  call s:IssueCStackListCmd()
  call s:SendCommand('-stack-info-frame')
endfunc

func! TermDebugGetScriptVar(name)
  return s:{a:name}
endfunc

func! TermDebugSetScriptVar(name, val)
  let s:{a:name} = a:val
endfunc

" s:TravelStackImpl: travel up/down the stack {{{
" Description: 
function! s:TravelStackImpl(gdbcmd, delta)
  let winnum = bufwinid(s:stackbuf)
  if winnum == -1 
    call s:SendCommand(a:gdbcmd)
  else
    call win_gotoid(winnum)
    let lnum = search('^>', 'wn')
    let nextline = lnum + a:delta
    if nextline < 1 || nextline > line('$')
      return
    endif
    call s:GotoSelectedFrame(nextline)
  endif
endfunction " }}}

function! TermDebugDownStack()
  call s:TravelStackImpl('down', -1)
endfunc

function! TermDebugUpStack()
  call s:TravelStackImpl('up', 1)
endfunc

func! s:GotoSelectedFrame(bufline)
  let lineText = getline(a:bufline)
  let matches = matchlist(lineText, '#\(\d\+\)\s\+\(\S\+\) at \(\S\+\):\(\d\+\) (\([CM]\))')
  if len(matches) == 0
    return
  endif

  let framenum = matches[1]
  let fcnname = matches[2]
  let filename = matches[3]
  let linenum = matches[4]
  let s:current_frame_type = matches[5]

  " We need to remember this for CTRL-P (see PrintHelper)
  let s:current_frame_idx = framenum
  exec 'keeppatterns silent! % s/^>/ /e'
  exec 'keeppatterns silent! '.a:bufline.' s/^ />/e'
  call s:OpenCursorPosition(filename, linenum)
  if s:current_frame_type == 'C'
    " For C frames, we also need to communicate the frame level to GDB so
    " CTRL-P etc. works.
    call TermDebugSendCommand("frame ".framenum)
  endif
endfunc

func! s:GetMiValue(txt, varname)
  return matchstr(a:txt, a:varname.'="\zs[^"]*\ze"')
endfunc

func! s:UpdateFramePtr(level)
  let winnum = bufwinid(s:stackbuf)
  if winnum == -1
    return
  endif

  let curwin = win_getid()
  call win_gotoid(winnum)
  exec 'keeppatterns silent! % s/^>/ /e'

  let marker = '('.s:current_frame_type.')'
  exec 'keeppatterns silent! % s/^ \ze#'.a:level.' .*'.marker.'/>/e'
  call win_gotoid(curwin)
endfunction
func! s:handleMCStackSwitching(msg)
    let fname = s:GetFullname(a:msg)
    let fcnname = s:GetMiValue(a:msg, 'func')
    if fname =~'SFXDebugCallbackHandler' && fcnname =~'MATLAB_GDB_Debugger' && a:msg!~ '^=thread-selected' && s:stoppedInMATLAB == v:false
        let s:stoppedInMATLAB = v:true
        call s:ShowMStack()
        return v:true
    endif
    if a:msg!~ '^=thread-selected' && s:current_stack_type == 'm'
        let s:current_stack_type = 'c'
        call s:ShowCStack()
        return v:true
    endif
    return v:false
endfunc
func! s:HandleCFrameOrStoppedMsg(msg)
  if a:msg =~ 'level='
    let level = s:GetMiValue(a:msg, 'level') + 0
  else
    let level = 0
  endif

  let s:current_frame_type = 'C'
  let s:current_frame_idx = level

  keepalt call s:UpdateFramePtr(level)

  let fname = s:GetFullname(a:msg)
  if filereadable(fname)
    let lnum = s:GetMiValue(a:msg, 'line') + 0
    if level == 0 && s:handleMCStackSwitching(a:msg)
        return
    endif
    keepalt call s:OpenCursorPosition(fname, lnum)
  endif
endfunc

func! s:UpdateStackIfVisible()
  let winid = bufwinid(s:stackbuf)
  if winid == -1
    return
  endif
  if s:current_stack_type =='c'
    call s:IssueCStackListCmd()
  elseif s:current_stack_type == 'h'
    call s:IssueHybridStackListCmd()
  elseif s:current_stack_type == 'm'
    call s:IssueMStackListCmd()
  endif
endfunc

func! s:ProcessCStackInfo(msg)
  let lines = []

  let lastknown = v:false
  let startpos = 0
  while 1
    let frame = matchstr(a:msg, 'frame={.\{-\}},', startpos)
    if frame == ''
      break
    endif

    let level = s:GetMiValue(frame, 'level') + 0
    let fcnname = substitute(s:GetMiValue(frame, 'func')," ","","g")
    let fcnname = fcnname[0:min([50,len(fcnname)])]
    let fname = s:GetFullname(frame)
    let lnum = s:GetMiValue(frame, 'line') + 0

    if fname == '' || fcnname == '' || lnum <= 0
        if lastknown == v:true
            call add(lines, ' ... ')
        endif
        let lastknown = v:false
    else
	let currentFrameStackText = printf(' #%-3d %s at %s:%d (C)' , level, fcnname, fname, lnum)
	call add(lines, currentFrameStackText)
        let lastknown = v:true
    endif

    let startpos += strlen(frame)
  endwhile

  return lines
endfunc

" s:UpdateStackWindow: updates stack window with lines {{{
" Description: 
function! s:UpdateStackWindow(lines)
  let curwin = win_getid()
  let winnum = s:ShowStackPre()
  
  " When we first render the stack, we cannot be sure that we are on the
  " very bottom of the stack. Therefore, the below is just a guess.
  " However, all the commands like Show[CMH]Stack issue a -stack-info-frame
  " which will place the > at the correct location.
  let a:lines[0] = substitute(a:lines[0], '^ ', '>', 'e')
  call win_gotoid(winnum)
  call deletebufline(s:stackbuf, 1, line('$'))
  call appendbufline(s:stackbuf, 0, a:lines)
  call cursor(1, 1)

  call win_gotoid(curwin)
endfunction " }}}

func! s:HandleMOrHybridStackInfo()
  let lines = split(s:hybrid_stack, '\\n')
  keepalt call s:UpdateStackWindow(lines)

  if s:current_stack_type == 'm'
    " for C or hybrid stacks, we would have issued a -stack-info-frame
    " command which refreshes the frame ptr etc. For MATLAB, we just use
    " the actual stack
    call s:GotoSelectedFrame(1)
  endif
endfunc

func! s:HandleCStackInfo(msg)
  let lines = s:ProcessCStackInfo(a:msg)
  keepalt call s:UpdateStackWindow(lines)
endfunc

func! s:Run(args)
  if a:args != ''
    call s:SendCommand('-exec-arguments ' . a:args)
  endif
  call s:SendCommand('-exec-run')
endfunc

func! s:SendEval(expr)
    if s:current_frame_type == "M"
        let pmlCmd = "printf \"%s\", SF::EvaluateCmdAtMATLABStackLevel(".s:current_frame_idx.",\"".a:expr."\")"."\r"
        call s:SendCommand(pmlCmd)
    else
        call s:SendCommand('-data-evaluate-expression "' . a:expr . '"')
    endif
  let s:evalexpr = a:expr
endfunc

" :Evaluate - evaluate what is under the cursor
func! s:Evaluate(range, arg)
  if a:arg != ''
    let expr = a:arg
  elseif a:range == 2
    let pos = getcurpos()
    let reg = getreg('v', 1, 1)
    let regt = getregtype('v')
    normal! gv"vy
    let expr = @v
    call setpos('.', pos)
    call setreg('v', reg, regt)
  else
    let expr = expand('<cexpr>')
  endif
  let s:ignoreEvalError = 0
  call s:SendEval(expr)
endfunc

" Handle the result of data-evaluate-expression
func! s:HandleEvaluate(msg)
  let value = substitute(a:msg, '.*value="\(.*\)"', '\1', '')
  let value = substitute(value, '\\"', '"', 'g')
  if s:current_frame_type == "M"
    let evalresultprefix = ''
    let value = value[2:len(value)-2]
  else
    let evalresultprefix = s:evalexpr . ':'
  endif
  if s:evalFromBalloonExpr
    if s:evalFromBalloonExprResult == ''
      let s:evalFromBalloonExprResult = evalresultprefix . value
    else
      let s:evalFromBalloonExprResult .= ' = ' . value
    endif
    let s:evalFromBalloonExprResult = substitute(s:evalFromBalloonExprResult,'"',"'","g")
    let s:evalFromBalloonExprResult = trim(eval('"'.s:evalFromBalloonExprResult.'"'))
    call balloon_show(s:evalFromBalloonExprResult)
  else
    echomsg '"' . evalresultprefix . value
  endif

  if s:evalexpr[0] != '*' && value =~ '^0x' && value != '0x0' && value !~ '"$'
    " Looks like a pointer, also display what it points to.
    let s:evalFromBalloonExpr = 0
    let s:ignoreEvalError = 1
    "call s:SendEval('*' . s:evalexpr)
  else
    let s:evalFromBalloonExpr = 0
  endif
endfunc

" Show a balloon with information of the variable under the mouse pointer,
" if there is any.
func! TermDebugBalloonExpr()
  if v:beval_winid != s:sourcewin
    return ''
  endif
  if !s:stopped
    " Only evaluate when stopped, otherwise setting a breakpoint using the
    " mouse triggers a balloon.
    return ''
  endif
  let s:evalFromBalloonExpr = 1
  let s:evalFromBalloonExprResult = ''
  let s:ignoreEvalError = 1
  call s:SendEval(v:beval_text)
  return ''
endfunc

" Handle an error.
func! s:HandleError(msg)
  if s:ignoreEvalError
    " Result of s:SendEval() failed, ignore.
    let s:ignoreEvalError = 0
    let s:evalFromBalloonExpr = 0
    return
  endif
  echoerr substitute(a:msg, '.*msg="\(.*\)"', '\1', '')
endfunc

func! s:GotoSourcewinOrCreateIt()
  let bn = -1
  " Iterating backwards because usually source windows occupy the
  " "bottom" part of a screen with supporting windows elsewhere
  for n in range(winnr('$'), 1, -1)
    let bn = winbufnr(n)
    if getbufvar(bn, '&buftype') != 'nofile'
	  \ && getbufvar(bn, '&buftype') != 'terminal'
      exec n.' wincmd w'
      break
    endif
  endfor
  if bn == -1
    botright new
  endif
  let s:sourcewin = win_getid(winnr())
  if !exists('g:termdebug_install_winbar') || g:termdebug_install_winbar
    call s:InstallWinbar()
  endif
endfunc

" s:OpenCursorPosition: sets the position of the program counter {{{
" Description: 
function! s:OpenCursorPosition(fname, lnum)
  if !filereadable(a:fname)
    return
  endif
  call s:GotoSourcewinOrCreateIt()
  if a:fname !~ @% 
    exec 'drop '.fnameescape(a:fname)
  elseif a:lnum <= line('w0') || a:lnum >= line('w$')
      " redraw when a:fname is currently visible but a:lnum is not
      redraw
  endif
  exe a:lnum
  exe 'sign unplace ' . s:pc_id
  exe 'sign place ' . s:pc_id . ' line=' . a:lnum . ' name=debugPC priority=110 file=' . a:fname
  if !exists('b:save_signcolumn')
    let b:save_signcolumn = &signcolumn
    call add(s:signcolumn_buflist, bufnr())
  endif
  setlocal signcolumn=yes
endfunction " }}}

" Handle stopping and running message from gdb. Updates the s:stopped
" variable which tracks whether GDB needs to be interrupted for issuing
" commands
func! s:HandleCursor(msg)
  " Issuing the hybrid_stack command (as part of UpdateStackIfVisible) when
  " we are stopped (due to a SIGINT) generates a SIGABORT which result in
  " GDB once again printing the *stopped message. This results in
  " HandleCursor getting called "recursively" which once again results in
  " hybrid_stack being issued. Hence we ignore *stopped messages received
  " when we are already stopped!
  if s:stopped == 0 && a:msg =~ '^\*stopped'
    let s:stopped = 1
    call foreground()

    let fname = s:GetFullname(a:msg)
    if filereadable(fname)
      " We can get to HandleCursor because of some very temporary *stopped
      " mssages (because of DLLs loading, temporarily interrupting GDB
      " etc.). Issuing these commands at this time usually results in GDB
      " errors. If the *stopped message has a readable filename, hopefully,
      " that's a "real" stop.
      call s:UpdateStackIfVisible()
      call s:HandleCFrameOrStoppedMsg(a:msg)
    endif

  elseif a:msg =~ '^\*running,thread-id="all"'
    let s:stopped = 0
    exe 'sign unplace ' . s:pc_id
    call s:UpdateFramePtr(-1)
  endif
endfunc

func! s:DefineBreakpointSign(id, subid, pending)
  let nr = printf('%d.%d', a:id, a:subid)

  let texthl = 'debugBreakpoint'
  if a:pending
    let texthl .= 'Pending'
  endif

  let signName = "debugBreakpoint".nr

  let s:breakpoint_signs[signName] = 1
  call s:Debug("sign define debugBreakpoint" . nr . " text=" . substitute(nr, '\..*', '', '') . " texthl=".texthl)
  exe "sign define debugBreakpoint" . nr . " text=" . substitute(nr, '\..*', '', '') . " texthl=".texthl
  return signName
endfunc

func! s:SplitMsg(s)
  return split(a:s, '{.\{-}}\zs')
endfunction

func! s:GetPendingFileName(msg)
  if a:msg !~ 'pending='
    return ["", -1]
  endif

  let name = s:DecodeMessage(substitute(a:msg, '.*pending=', '', ''))
  if has('win32') && name =~ ':\\\\'
    " sometimes the name arrives double-escaped
    let name = substitute(name, '\\\\', '\\', 'g')
  endif
  let matches = matchlist(name, '\(.*\):\(\d\+\)$', '')
  if empty(matches)
    return ["", -1]
  endif

  let name = matches[1]
  if !bufloaded(name)
    if expand('%:p') =~ name
      " We can get here when we put a "pending" breakpoint in the current
      " file. If TermdebugCurrentLocation is set, the pending location
      " might not be the full path.
      let name = expand('%:p')
    endif
  end
  let lnum = matches[2]
  return [name, lnum]
endfunction

func! s:EndsWith(larger, smaller)
  return strlen(a:larger) > strlen(a:smaller) && 
	\ strpart(a:larger, strlen(a:larger) - strlen(a:smaller)) == a:smaller
endfunction

func! s:TryToResolveName(name)
  if bufloaded(a:name)
    return a:name
  endif

  for bufnum in range(1, bufnr('$'))
    if s:EndsWith(fnamemodify(bufname(bufnum), ':p'), a:name)
      return bufname(bufnum)
    endif
  endfor

  return a:name
endfunction

" Handle setting a breakpoint
" Will update the sign that shows the breakpoint
func! s:HandleBreakpointCreated(msg)
  if a:msg =~ 'type="hw watch"'
    " a watch does not have a file name
    return
  endif
  for msg in s:SplitMsg(a:msg)
    let fname = s:GetFullname(msg)
    let lnum = substitute(msg, '.*line="\([^"]*\)".*', '\1', '')
    " call s:Debug('s:HandleBreakpointCreated: msg = '.msg.', fname = '.fname.', lnum = '.lnum)
    let pending = v:false
    if empty(fname)
      let [fname, lnum] = s:GetPendingFileName(msg)
      let pending = v:true
      if !empty(fname)
	let fname = s:TryToResolveName(fname)
      endif
    endif
    if empty(fname)
      call s:Debug("empty filename! continuing")
      continue
    endif
    let nr = substitute(msg, '.*number="\([0-9.]*\)\".*', '\1', '')
    if empty(nr)
      return
    endif

    " If "nr" is 123 it becomes "123.0" and subid is "0".
    " If "nr" is 123.4 it becomes "123.4.0" and subid is "4"; "0" is discarded.
    let [id, subid; _] = map(split(nr . '.0', '\.'), 'v:val + 0')
    call s:DefineBreakpointSign(id, subid, pending)

    if has_key(s:breakpoints, id)
      let entries = s:breakpoints[id]
    else
      let entries = {}
      let s:breakpoints[id] = entries
    endif
    if has_key(entries, subid)
      let entry = entries[subid]
    else
      let entry = {}
      let entries[subid] = entry
    endif

    let entry['id'] = id
    let entry['subid'] = subid
    let entry['fname'] = fname
    let entry['lnum'] = lnum
    let entry['placed'] = 0

    if bufloaded(fname)
      call s:PlaceSign(id, subid, entry)
    endif
  endfor
endfunc

func! s:PlaceSign(id, subid, entry)
  let nr = printf('%d.%d', a:id, a:subid)
  let signId = s:Breakpoint2SignNumber(a:id, a:subid)
  call s:Debug('placing sign in '.a:entry['fname'].' at line '.a:entry['lnum'])
  call sign_place(signId, 
	\ 'TermDebugBreakpoints', 'debugBreakpoint'.nr, a:entry['fname'], {
	  \ 'lnum': a:entry['lnum'],
	  \ })

  let a:entry['placed'] = 1
endfunc

sign define debugBreakpointPending text=? texthl=debugBreakpointPending
func! s:TogglePendingBreakpoint()
  let info = sign_getplaced(bufname(), {'group': 'TermDebugPendingBreakpoints', 'lnum': line('.')})
  if empty(info[0]['signs'])
    call sign_place(0, 
	  \ 'TermDebugPendingBreakpoints', 'debugBreakpointPending', '%', {
	    \ 'lnum': line('.'),
	    \ })
  else
    call sign_unplace('TermDebugPendingBreakpoints', {'buffer': bufname(), 'id': info[0]['signs'][0]['id']})
  endif
endfunc

func! s:GetSignLocations(groupName)
  let bps = []
  for bufnr in range(1, bufnr('$'))
    if !buflisted(bufnr) || empty(bufname(bufnr))
      continue
    endif
    let lnumsfound = {}
    let signs = sign_getplaced(bufname(bufnr), {'group': a:groupName})
    let signs = signs[0]['signs']
    for sign in signs
      if get(lnumsfound, sign['lnum'], 0) == 0
	let bps += [{'fname': expand('#'.bufnr.':p'), 'lnum': sign['lnum']}]
      endif
      let lnumsfound[sign['lnum']] = 1
    endfor
  endfor
  return bps
endfunc

func! s:DeleteBreakpoint(id)
  if has_key(s:breakpoints, a:id)

    for [subid, entry] in items(s:breakpoints[a:id])
      if has_key(entry, 'placed')
	call s:UnplaceBreakpointSign(a:id, subid)
      endif
    endfor

    unlet s:breakpoints[a:id]
  endif
endfunc

" Handle deleting a breakpoint
" Will remove the sign that shows the breakpoint
func! s:HandleBreakpointDeleted(msg)
  let id = substitute(a:msg, '.*id="\([0-9]*\)\".*', '\1', '') + 0
  if empty(id)
    return
  endif
  call s:DeleteBreakpoint(id)
endfunc

" Handle a breakpoint modification
" Will update the sign that shows the breakpoint
func! s:HandleBreakpointModified(msg)
  let id = substitute(a:msg, '.*number="\([0-9]*\)\".*', '\1', '') + 0
  call s:DeleteBreakpoint(id)
  call s:HandleBreakpointCreated(a:msg)
endfunc

func! s:RestoreBreakpoints()
  call s:Debug('sending break-list')
  call s:SendCommand('-break-list')
endfunc

func! s:HandleBreakpointInfo(msg)
  call s:Debug("Getting to HandleBreakpointInfo ".a:msg)
  let startpos = 0

  let num = 0
  while startpos < strlen(a:msg)
    let bpinfo = matchstr(a:msg, 'bkpt={.\{-\}}', startpos)
    if empty(bpinfo)
      break
    endif
    let startpos += strlen(bpinfo)

    let num = s:GetMiValue(bpinfo, "number") + 0
  endwhile

  let bps = s:GetSignLocations('TermDebugPendingBreakpoints')
  call sign_unplace('TermDebugPendingBreakpoints')

  for bp in bps
    let fname = bp['fname']
    if exists('*TermdebugFilenameModifier')
      let fname = TermdebugFilenameModifier(fname)
    endif
    let location = fname.':'.bp['lnum']
    call s:SetBreakpoint(location)
  endfor
endfunc

" Handle the debugged program starting to run.
" Will store the process ID in s:pid
func! s:HandleProgramRun(msg)
  let nr = substitute(a:msg, '.*pid="\([0-9]*\)\".*', '\1', '') + 0
  if nr == 0
    return
  endif
  let s:pid = nr
  " call ch_log('Detected process ID: ' . s:pid)
endfunc

" Handle a BufRead autocommand event: place any signs.
func! s:BufRead()
  let fname = expand('<afile>:p')
  for [id, entries] in items(s:breakpoints)
    for [subid, entry] in items(entries)
      if entry['fname'] == fname
	call s:PlaceSign(id, subid, entry)
      endif
    endfor
  endfor
endfunc

" Handle a BufUnloaded autocommand event: unplace any signs.
func! s:BufUnloaded()
  let fname = expand('<afile>:p')
  for [id, entries] in items(s:breakpoints)
    for [subid, entry] in items(entries)
      if entry['fname'] == fname
	let entry['placed'] = 0
      endif
    endfor
  endfor
endfunc

" TermDebugSendCommandToComm: sends the command to the gdb communication window {{{
" Description: 
function! TermDebugSendCommandToComm(cmd)
  call s:SendCommand(a:cmd)
endfunction " }}}

let &cpo = s:keepcpo
unlet s:keepcpo
" vim: sw=2 ts=8 noet 
