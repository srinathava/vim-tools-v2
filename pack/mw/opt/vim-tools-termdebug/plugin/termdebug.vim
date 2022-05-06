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

" In case this gets sourced twice.
if exists(':Termdebug')
  finish
endif

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

let s:pc_id = 12
let s:asm_id = 13
let s:break_id = 13  " breakpoint number is added to this
let s:stopped = 1

let s:parsing_disasm_msg = 0
let s:asm_lines = []
let s:asm_addr = ''

let s:path = expand('<sfile>:p:h')
exec 'pyxfile '.s:path.'/init_logging.py'
pyx initLogging()
func s:Debug(msg)
  exec "pyx log(r'''".a:msg."''')"
endfunction

" Take a breakpoint number as used by GDB and turn it into an integer.
" The breakpoint may contain a dot: 123.4 -> 123004
" The main breakpoint has a zero subid.
func s:Breakpoint2SignNumber(id, subid)
  return s:break_id + a:id * 1000 + a:subid
endfunction

func s:Highlight(init, old, new)
  let default = a:init ? 'default ' : ''
  if a:new ==# 'light' && a:old !=# 'light'
    exe "hi " . default . "debugPC term=reverse ctermbg=lightblue guibg=lightblue"
  elseif a:new ==# 'dark' && a:old !=# 'dark'
    exe "hi " . default . "debugPC term=reverse ctermbg=darkblue guibg=darkblue"
  endif
  hi default debugBreakpoint term=reverse ctermbg=red guibg=red
endfunc

call s:Highlight(1, '', &background)

au ColorScheme * call s:Highlight(1, '', &background)

func s:StartDebug(bang, ...)
  " First argument is the command to debug, second core file or process ID.
  call s:StartDebug_internal({'gdb_args': a:000, 'bang': a:bang})
endfunc

func s:StartDebugCommand(bang, ...)
  " First argument is the command to debug, rest are run arguments.
  call s:StartDebug_internal({'gdb_args': [a:1], 'proc_args': a:000[1:], 'bang': a:bang})
endfunc

func s:StartDebug_internal(dict)
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

func s:CloseBuffers()
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

func s:UseSeparateTTYForProgram()
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
    let ptybuf = term_start(a:cmd, {
	  \ 'term_name': term_name,
	  \ 'vertical': vertical,
	  \ 'out_cb': OutCB,
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
  end
  return {
	\ 'buffer': ptybuf,
	\ 'pty': pty,
	\ 'jobid': jobid
	\ }
endfunction

func s:StartDebug_term(dict)
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

  let s:gdbDoneInitializing = 0
  while !s:gdbDoneInitializing
    sleep 10m
  endwhile
endfunc

func s:OnGdbMainOutput(dict, chan, msg)
  if s:foundGdbPrompt
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
    let s:gdbDoneInitializing = 1
  endif
endfunc

func s:HasGdbProcessExited()
  if has('nvim')
    return nvim_get_chan_info(s:gdbjob['jobid']) == {}
  else
    let gdbproc = term_getjob(s:gdbjob['buffer'])
    return gdbproc == v:null || job_status(gdbproc) !=# 'run'
  endif
endfunc

" s:TermGetLine:  {{{
" Description: 
function! s:TermGetLine(job, lnum)
  let bufid = a:job['buffer']
  if has('nvim')
    return get(getbufline(bufid, a:lnum), 0, '')
  else
    return term_getline(bufid, a:lnum)
  endif
endfunction " }}}

func s:StartDebug_term_step2(dict)
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

func s:StartDebug_prompt(dict)
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

func s:StartDebugCommon(dict)
  " Sign used to highlight the line where the program has stopped.
  " There can be only one.
  sign define debugPC linehl=debugPC

  " Install debugger commands in the text window.
  call win_gotoid(s:sourcewin)
  call s:InstallCommands()
  call win_gotoid(s:gdbwin)

  " Enable showing a balloon with eval info
  if has("balloon_eval") || has("balloon_eval_term")
    set balloonexpr=TermDebugBalloonExpr()
    if has("balloon_eval")
      set ballooneval
    endif
    if has("balloon_eval_term")
      set balloonevalterm
    endif
  endif

  tnoremap <ScrollWheelUp> <C-W>N<ScrollWheelUp>

  if exists('g:termdebug_persist_breakpoints') && g:termdebug_persist_breakpoints && exists('s:breakpoints')
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

    " Contains breakpoints by file/lnum.  The key is "fname:lnum".
    " Each entry is a list of breakpoint IDs at that position.
    let s:breakpoint_locations = {}
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

  doautocmd User TermDebugStarted
  if has('nvim')
    normal! Ga
  endif
endfunc

" Send a command to gdb.  "cmd" is the string without line terminator.
func s:SendCommand(cmd)
  " call ch_log('sending to gdb: ' . a:cmd)
  if s:way == 'prompt'
    call ch_sendraw(s:gdb_channel, a:cmd . "\n")
  else
    call s:TermSendKeys(s:commjob, a:cmd . "\r")
  endif
endfunc

" This is global so that a user can create their mappings with this.
func TermDebugSendCommand(cmd)
  if s:way == 'prompt'
    call ch_sendraw(s:gdb_channel, a:cmd . "\n")
  else
    if !s:stopped
      call s:SendCommand('-exec-interrupt')
      sleep 10m
    endif
    call s:TermSendKeys(s:gdbjob, a:cmd . "\r")
  endif
endfunc

" Function called when entering a line in the prompt buffer.
func s:PromptCallback(text)
  call s:SendCommand(a:text)
endfunc

" Function called when pressing CTRL-C in the prompt buffer and when placing a
" breakpoint.
func s:PromptInterrupt()
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
func s:GdbOutCallback(channel, text)
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
func s:DecodeMessage(quotedText)
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
func s:GetFullname(msg)
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

func s:WipeJobBuffer(job)
  if !empty(a:job) && a:job['buffer'] > 0
    exe 'bwipe! '.a:job['buffer']
  endif
endfunc

func s:EndTermDebug(...)
  call s:CloseBuffers()
  call s:EndDebugCommon()
endfunc

func s:EndDebugCommon()
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
endfunc

func s:EndPromptDebug(job, status)
  let curwinid = win_getid(winnr())
  call win_gotoid(s:gdbwin)
  set nomodified
  close
  if curwinid != s:gdbwin
    call win_gotoid(curwinid)
  endif

  call s:EndDebugCommon()
  unlet s:gdbwin
  " call ch_log("Returning from EndPromptDebug()")
endfunc

" Handle a message received from gdb on the GDB/MI interface.
func s:CommOutput(chan, msg)
  let msgs = split(a:msg, "\r")

  for msg in msgs
    " remove prefixed NL
    if msg[0] == "\n"
      let msg = msg[1:]
    endif
    if msg != ''
      if msg =~ '^\(\*stopped\|\*running\|=thread-selected\)'
	call s:HandleCursor(msg)
	call s:HandleFrameInfo(msg)
      elseif msg =~ '^\^done,bkpt=' || msg =~ '^=breakpoint-created,'
	call s:HandleBreakpointCreated(msg)
      elseif msg =~ '^\^done,BreakpointTable='
	call s:HandleBreakpointInfo(msg)
      elseif msg =~ '^=breakpoint-deleted,'
	call s:HandleBreakpointDeleted(msg)
      elseif msg =~ '^=breakpoint-modified,'
	call s:HandleBreakpointModified(msg)
      elseif msg =~ '^\^done,stack='
	call s:HandleStackInfo(msg)
      elseif msg =~ '^\^done,frame='
	call s:HandleFrameInfo(msg)
      elseif msg =~ '^=thread-group-started'
	call s:HandleProgramRun(msg)
      elseif msg =~ '^\^done,value='
	call s:HandleEvaluate(msg)
      elseif msg =~ '^\^error,msg='
	call s:HandleError(msg)
      endif
    endif
  endfor
endfunc

func s:GotoProgram()
  if has('win32')
    if executable('powershell')
      call system(printf('powershell -Command "add-type -AssemblyName microsoft.VisualBasic;[Microsoft.VisualBasic.Interaction]::AppActivate(%d);"', s:pid))
    endif
  else
    call win_gotoid(s:ptywin)
  endif
endfunc

" Install commands in the current window to control the debugger.
func s:InstallCommands()
  call s:Debug("Installing commands")
  let save_cpo = &cpo
  set cpo&vim

  command! -nargs=? Break call s:SetBreakpoint(<q-args>)
  command! -nargs=? Until call s:Until(<q-args>)
  command! -nargs=? Jump call s:Jump(<q-args>)
  command! Clear call s:ClearBreakpoint()
  command! Step call s:SendCommand('-exec-step')
  command! Over call s:SendCommand('-exec-next')
  " Use finish so that GDB displays the helpful return value
  command! Finish call s:SendCommand('finish')
  command! -nargs=* Run call s:Run(<q-args>)
  command! -nargs=* Arguments call s:SendCommand('-exec-arguments ' . <q-args>)
  command! Stop call s:SendCommand('-exec-interrupt')
  command! -nargs=* GDB call TermDebugSendCommand(<q-args>)
  command! Stack call s:ShowStack()
  command! ToggleBreakpoint call s:ToggleBreakpoint()

  " using -exec-continue results in CTRL-C in gdb window not working
  if s:way == 'prompt'
    command! Continue call s:SendCommand('continue')
  else
    command! Continue call s:TermSendKeys(s:gdbjob, "continue\r")
  endif

  command! -range -nargs=* Evaluate call s:Evaluate(<range>, <q-args>)
  command! ShowGdb call s:ShowGdb()
  command! ShowProgram call win_gotoid(s:ptywin)
  command! Source call s:GotoSourcewinOrCreateIt()
  command! Winbar call s:InstallWinbar()

  if !exists('g:termdebug_map_K') || g:termdebug_map_K
    let s:k_map_saved = maparg('K', 'n', 0, 1)
    nnoremap K :Evaluate<CR>
  endif

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
  end
endfunc

let s:winbar_winids = []

" Install the window toolbar in the current window.
func s:InstallWinbar()
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

func s:ClearBreakpointInfo()
  for [id, entries] in items(s:breakpoints)
    for subid in keys(entries)
      call s:UnplaceBreakpointSign(id, subid)
    endfor
  endfor
  let s:breakpoints = {}
  let s:breakpoint_locations = {}

  for val in s:BreakpointSigns
    call s:Debug('undefining sign')
    exe "sign undefine debugBreakpoint" . val
  endfor
  let s:BreakpointSigns = []
endfunc

" Delete installed debugger commands in the current window.
func s:DeleteCommands()
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

  if exists('s:k_map_saved') && !empty(s:k_map_saved)
    call mapset('n', 0, s:k_map_saved)
    unlet s:k_map_saved
  endif

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

  if !exists('g:termdebug_persist_breakpoints') || !g:termdebug_persist_breakpoints
    call s:ClearBreakpointInfo()
  endif
endfunc

func s:LocationCmd(at, cmd)
  " Setting a breakpoint may not work while the program is running.
  " Interrupt to make it work.
  let do_continue = 0
  if !s:stopped
    let do_continue = 1
    if s:way == 'prompt'
      call s:PromptInterrupt()
    else
      call s:SendCommand('-exec-interrupt')
    endif
    sleep 10m
  endif
  if !empty(a:at)
    let at = a:at
  elseif exists('*TermdebugFilenameModifier')
    let at = TermdebugFilenameModifier(expand('%:p')) . ':' . line('.')
  else
    " Use the fname:lnum format, older gdb can't handle --source.
    let at = fnameescape(expand('%:p')) . ':' . line('.')
  end

  call s:SendCommand(a:cmd.' '.at)
  if do_continue
    call s:SendCommand('-exec-continue')
  endif
endfunc

" :Break - Set a breakpoint at the cursor position.
func s:SetBreakpoint(at)
  " Use break instead of -break-insert. -break-insert does not seem to
  " honor "set breakpoint pending on" option.
  call s:LocationCmd(a:at, 'break')
endfunc

func s:UnplaceBreakpointSign(id, subid)
   exe 'sign unplace ' . s:Breakpoint2SignNumber(a:id, a:subid).' group=TermDebugBreakpoints'
endfunc

" :Clear - Delete a breakpoint at the cursor position.
func s:ClearBreakpoint()
  let fname = fnameescape(expand('%:p'))
  let lnum = line('.')
  let bploc = printf('%s:%d', fname, lnum)
  if has_key(s:breakpoint_locations, bploc)
    let idx = 0
    for id in s:breakpoint_locations[bploc]
      if has_key(s:breakpoints, id)
	" Assume this always works, the reply is simply "^done".
	call s:SendCommand('-break-delete ' . id)
	for subid in keys(s:breakpoints[id])
	  call s:UnplaceBreakpointSign(id, subid)
	endfor
	unlet s:breakpoints[id]
	unlet s:breakpoint_locations[bploc][idx]
	break
      else
	let idx += 1
      endif
    endfor
    if empty(s:breakpoint_locations[bploc])
      unlet s:breakpoint_locations[bploc]
    endif
  endif
endfunc

func s:ToggleBreakpoint()
  let fname = fnameescape(expand('%:p'))
  let lnum = line('.')
  let bploc = printf('%s:%d', fname, lnum)
  if has_key(s:breakpoint_locations, bploc) && !empty(s:breakpoint_locations[bploc])
    call s:Debug('clearing breakpoint at '.bploc)
    call s:ClearBreakpoint()
  else
    call s:Debug('setting breakpoint at '.bploc)
    call s:SetBreakpoint('')
  endif
endfunc

func s:Until(at)
  call s:LocationCmd(a:at, 'until')
endfunc

func s:Jump(at)
  call s:LocationCmd(a:at, 'tbreak')
  call s:LocationCmd(a:at, 'jump')
endfunc

func s:IssueStackListCmd(winid)
  call s:Debug('-stack-list-frames 0 '.(winheight(a:winid)-2))
  call s:SendCommand('-stack-list-frames 0 '.(winheight(a:winid)-2))
  call s:SendCommand('-stack-info-frame')
endfunc

func s:ShowStack()
  let curwinid = win_getid()
  if s:stackbuf == -1
    let s:stackbuf = bufnr('__GDB_Stack__', 1) 
    call setbufvar(s:stackbuf, '&swapfile', 0)
    call setbufvar(s:stackbuf, '&buflisted', 0)
    call setbufvar(s:stackbuf, '&buftype', 'nofile')
    call setbufvar(s:stackbuf, '&ts', 8)
  endif

  let winnum = bufwinid(s:stackbuf)
  if winnum != -1
    call win_gotoid(winnum)
  else
    if win_gotoid(s:gdbwin)
      exec 'vert sbuffer '.s:stackbuf
    else
      exec 'sbuffer '.s:stackbuf
    endif
  endif
  let winnum = bufwinid(s:stackbuf)

  setlocal nowrap
  nmap <buffer> <silent> <CR>           :call <SID>GotoSelectedFrame()<CR>
  nmap <buffer> <silent> <2-LeftMouse>  :call <SID>GotoSelectedFrame()<CR>
  nmap <buffer> <silent> <tab>          :call <SID>ExpandStack()<CR>

  call s:Debug('setting up stack in '.winnum)
  call s:IssueStackListCmd(winnum)
  call win_gotoid(curwinid)
endfunc

func TermDebugScriptVar(name)
  return s:{a:name}
endfunc

func s:GotoSelectedFrame()
  let level = matchstr(getline('.'), '\d\+')
  if level != ''
    " Use frame instead of -stack-select-frame so GDB prints the
    " =thread-selected message on the MI console which triggers
    " s:HandleCursor
    call s:SendCommand('frame '.level)
  endif
endfunc

func s:ExpandStack()
  if getline('$') !~ 'next frame'
    return
  endif

  let nextframe = matchstr(getline('$'), 'next frame = \zs\d\+\ze') + 0
  call s:SendCommand('-stack-list-frames '.nextframe.' '.(nextframe + winheight(0)-2))
endfunc

func s:GetMiValue(txt, varname)
  return matchstr(a:txt, a:varname.'="\zs[^"]*\ze"')
endfunc

func s:UpdateFramePtr(winnum, level)
  call win_gotoid(a:winnum)
  exec 'keeppatterns silent! % s/^>/ /e'
  exec 'keeppatterns silent! % s/^ #\('.a:level.'\) />#\1 /e'
endfunction

func s:HandleFrameInfo(msg)
  if a:msg !~ 'level='
    return
  endif

  let winnum = bufwinid(s:stackbuf)
  if winnum == -1
    return
  endif

  let level = s:GetMiValue(a:msg, 'level') + 0
  let curwin = win_getid()
  keepalt call s:UpdateFramePtr(winnum, level)
  call win_gotoid(curwin)
endfunc

func s:UpdateStackIfVisible()
  let winid = bufwinid(s:stackbuf)
  if winid == -1
    return
  endif
  call s:IssueStackListCmd(winid)
endfunc

func s:UpdateStackWindow(msg)
  let startpos = 0
  call deletebufline(s:stackbuf, line('$'))

  let lastknown = v:false
  let numnewframes = 0
  while startpos < strlen(a:msg)
    let frame = matchstr(a:msg, 'frame={.\{-\}}', startpos)
    if frame == ''
      break
    endif
    let numnewframes += 1

    let level = s:GetMiValue(frame, 'level') + 0
    if level == 0
      " This means that we got a fresh stack.
      call deletebufline(s:stackbuf, 1, line('$'))
    endif
    let fcnname = s:GetMiValue(frame, 'func')
    let fname = s:GetFullname(frame)
    let lnum = s:GetMiValue(frame, 'line') + 0

    if fname != ''
      call append(line('$'), printf(' #%-3d %s(...) at %s:%d' , level, fcnname, fname, lnum))
      let lastknown = v:true
    else
      if lastknown == v:true
	call append(line('$'), ' ... ')
      endif
      let lastknown = v:false
    endif

    let startpos += strlen(frame)
  endwhile

  if numnewframes >= winheight(0)-1
    " There is a slim chance that we might have resized the stack
    " window after issuing the -stack-list-frames command. In which
    " case, this line will not get emitted
    call append(line('$'), printf('Press <tab> to show more frames. (next frame = %d)', level+1))
  else
    call append(line('$'), 'No more frames')
  endif
  if getline(1) == ''
    call deletebufline(s:stackbuf, 1)
  endif
endfunc

func s:HandleStackInfo(msg)
  let winnum = bufwinid(s:stackbuf)
  if winnum == -1
    return
  endif
  let curwin = win_getid()
  call win_gotoid(winnum)
  keepalt call s:UpdateStackWindow(a:msg)
  call win_gotoid(curwin)
endfunc

func s:Run(args)
  if a:args != ''
    call s:SendCommand('-exec-arguments ' . a:args)
  endif
  call s:SendCommand('-exec-run')
endfunc

func s:SendEval(expr)
  call s:SendCommand('-data-evaluate-expression "' . a:expr . '"')
  let s:evalexpr = a:expr
endfunc

" :Evaluate - evaluate what is under the cursor
func s:Evaluate(range, arg)
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

let s:ignoreEvalError = 0
let s:evalFromBalloonExpr = 0

" Handle the result of data-evaluate-expression
func s:HandleEvaluate(msg)
  let value = substitute(a:msg, '.*value="\(.*\)"', '\1', '')
  let value = substitute(value, '\\"', '"', 'g')
  if s:evalFromBalloonExpr
    if s:evalFromBalloonExprResult == ''
      let s:evalFromBalloonExprResult = s:evalexpr . ': ' . value
    else
      let s:evalFromBalloonExprResult .= ' = ' . value
    endif
    call balloon_show(s:evalFromBalloonExprResult)
  else
    echomsg '"' . s:evalexpr . '": ' . value
  endif

  if s:evalexpr[0] != '*' && value =~ '^0x' && value != '0x0' && value !~ '"$'
    " Looks like a pointer, also display what it points to.
    let s:ignoreEvalError = 1
    call s:SendEval('*' . s:evalexpr)
  else
    let s:evalFromBalloonExpr = 0
  endif
endfunc

" Show a balloon with information of the variable under the mouse pointer,
" if there is any.
func TermDebugBalloonExpr()
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
func s:HandleError(msg)
  if s:ignoreEvalError
    " Result of s:SendEval() failed, ignore.
    let s:ignoreEvalError = 0
    let s:evalFromBalloonExpr = 0
    return
  endif
  echoerr substitute(a:msg, '.*msg="\(.*\)"', '\1', '')
endfunc

func s:GotoSourcewinOrCreateIt()
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

" Handle stopping and running message from gdb.
" Will update the sign that shows the current position.
func s:HandleCursor(msg)
  let wid = win_getid(winnr())

  if a:msg =~ '^\*stopped'
    " call ch_log('program stopped')
    let s:stopped = 1
  elseif a:msg =~ '^\*running,thread-id="all"'
    " call ch_log('program running')
    let s:stopped = 0
  endif

  if a:msg =~ 'fullname='
    let fname = s:GetFullname(a:msg)
  else
    let fname = ''
  endif
  if a:msg =~ '^\(\*stopped\|=thread-selected\)' && filereadable(fname)
    let lnum = substitute(a:msg, '.*line="\([^"]*\)".*', '\1', '')
    if lnum =~ '^[0-9]*$'
      call s:GotoSourcewinOrCreateIt()
      if expand('%:p') != fnamemodify(fname, ':p')
	exec 'drop '.fnameescape(fname)
      endif
      exe lnum
      call s:Debug('placing current cursor sign')
      exe 'sign unplace ' . s:pc_id
      exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=debugPC priority=110 file=' . fname
      if !exists('b:save_signcolumn')
	let b:save_signcolumn = &signcolumn
	call add(s:signcolumn_buflist, bufnr())
      endif
      setlocal signcolumn=yes

      call foreground()
      call s:UpdateStackIfVisible()
      redraw
    endif
  elseif !s:stopped || fname != ''
    exe 'sign unplace ' . s:pc_id
  endif

  call win_gotoid(wid)
endfunc

let s:BreakpointSigns = []

func s:CreateBreakpoint(id, subid)
  let nr = printf('%d.%d', a:id, a:subid)
  if index(s:BreakpointSigns, nr) == -1
    call add(s:BreakpointSigns, nr)
    call s:Debug("sign define debugBreakpoint" . nr . " text=" . substitute(nr, '\..*', '', '') . " texthl=debugBreakpoint")
    exe "sign define debugBreakpoint" . nr . " text=" . substitute(nr, '\..*', '', '') . " texthl=debugBreakpoint"
  endif
endfunc

func s:SplitMsg(s)
  return split(a:s, '{.\{-}}\zs')
endfunction

func s:GetPendingFileName(msg)
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

" Handle setting a breakpoint
" Will update the sign that shows the breakpoint
func s:HandleBreakpointCreated(msg)
  if a:msg =~ 'type="hw watch"'
    " a watch does not have a file name
    return
  endif
  call s:Debug('s:HandleBreakpointCreated: msg = '.a:msg)
  for msg in s:SplitMsg(a:msg)
    let fname = s:GetFullname(msg)
    let lnum = substitute(msg, '.*line="\([^"]*\)".*', '\1', '')
    if empty(fname)
      let [fname, lnum] = s:GetPendingFileName(a:msg)
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
    call s:CreateBreakpoint(id, subid)

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

    let entry['fname'] = fname
    let entry['lnum'] = lnum

    let bploc = printf('%s:%d', fname, lnum)
    if !has_key(s:breakpoint_locations, bploc)
      let s:breakpoint_locations[bploc] = []
    endif
    let s:breakpoint_locations[bploc] += [id]

    if bufloaded(fname)
      call s:PlaceSign(id, subid, entry)
    endif
  endfor
endfunc

func s:PlaceSign(id, subid, entry)
  let nr = printf('%d.%d', a:id, a:subid)
  let signId = s:Breakpoint2SignNumber(a:id, a:subid)
  call sign_place(signId, 
	      \ 'TermDebugBreakpoints', 'debugBreakpoint'.nr, a:entry['fname'], {
	      \ 'lnum': a:entry['lnum'],
	      \ })

  let a:entry['placed'] = 1
endfunc

func s:DeleteBreakpoint(id)
  if has_key(s:breakpoints, a:id)

    for [subid, entry] in items(s:breakpoints[a:id])

      if has_key(entry, 'placed')
	call s:UnplaceBreakpointSign(a:id, subid)
	unlet entry['placed']
      endif

      let fname = entry['fname']
      let lnum = entry['lnum']
      let bploc = printf('%s:%d', fname, lnum)
      let idx = index(s:breakpoint_locations[bploc], a:id)
      call remove(s:breakpoint_locations[bploc], idx)

    endfor

    unlet s:breakpoints[a:id]
  endif
endfunc

" Handle deleting a breakpoint
" Will remove the sign that shows the breakpoint
func s:HandleBreakpointDeleted(msg)
  let id = substitute(a:msg, '.*id="\([0-9]*\)\".*', '\1', '') + 0
  if empty(id)
    return
  endif
  call s:DeleteBreakpoint(id)
endfunc

" Handle a breakpoint modification
" Will update the sign that shows the breakpoint
func s:HandleBreakpointModified(msg)
  let id = substitute(a:msg, '.*number="\([0-9]*\)\".*', '\1', '') + 0
  call s:DeleteBreakpoint(id)
  call s:HandleBreakpointCreated(a:msg)
endfunc

func s:RestoreBreakpoints()
  call s:SendCommand('-break-list')
endfunc

func s:HandleBreakpointInfo(msg)
  call s:Debug("Getting to HandleBreakpointInfo ".a:msg)
  let startpos = 0

  let num = 0
  while startpos < strlen(a:msg)
    let bpinfo = matchstr(a:msg, 'bkpt={.\{-\}}', startpos)
    if empty(bpinfo)
      break
    end
    let startpos += strlen(bpinfo)

    let num = s:GetMiValue(bpinfo, "number") + 0
  endwhile

  let locations = []
  for [id, entries] in items(s:breakpoints)
    if id > num
      for [subid, entry] in items(entries)
	let filename = entry['fname']
	if exists('*TermdebugFilenameModifier')
	  let filename = TermdebugFilenameModifier(filename)
	endif
	let locations += [filename.':'.entry['lnum']]
      endfor
    endif
  endfor

  call s:Debug('Clearing breakpoints')
  call s:ClearBreakpointInfo()

  call s:Debug('Restoring breakpoints')
  for location in locations
    call s:SetBreakpoint(location)
  endfor

endfunc

" Handle the debugged program starting to run.
" Will store the process ID in s:pid
func s:HandleProgramRun(msg)
  let nr = substitute(a:msg, '.*pid="\([0-9]*\)\".*', '\1', '') + 0
  if nr == 0
    return
  endif
  let s:pid = nr
  " call ch_log('Detected process ID: ' . s:pid)
endfunc

" Handle a BufRead autocommand event: place any signs.
func s:BufRead()
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
func s:BufUnloaded()
  let fname = expand('<afile>:p')
  for [id, entries] in items(s:breakpoints)
    for [subid, entry] in items(entries)
      if entry['fname'] == fname
	let entry['placed'] = 0
      endif
    endfor
  endfor
endfunc

let &cpo = s:keepcpo
unlet s:keepcpo
" vim: sw=2 ts=8 noet
