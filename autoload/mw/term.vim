" =====================================================================================
" Terminal compatibility layer for Vim/Neovim
"
" Allows some limited terminal functionality to be used in a consistent
" manner on both vim and neovim.
" =====================================================================================
" mw#term#Start: nvim/vim compatible version for starting a new terminal {{{
" Description: 
function! mw#term#Start(cmd, opts={})
    let defaults = {
                \ 'term_name': '',
                \ 'vertical': v:false,
                \ 'bottom': v:false,
                \ 'out_cb' : function('s:DoNothing'),
                \ 'err_cb' : function('s:DoNothing'),
                \ 'exit_cb' : function('s:DoNothing'),
                \ 'hidden' : v:false,
                \ 'term_finish': 'open'
                \ }

    let opts = extend(a:opts, defaults, "keep")

    if !opts.hidden
        let split = opts.vertical ? 'vnew' : ( opts.bottom ? 'bot new' : 'new')
        execute split
    endif

    if has('nvim')
        if type(a:cmd) == v:t_string && a:cmd == 'NONE'
            let cmd = 'tail -f /dev/null;#'.opts.term_name
        else
            let cmd = a:cmd
        endif

        let cb_opts = {
                    \ 'on_stdout': function('s:NvimOutputWrapper', [opts.out_cb]),
                    \ 'on_stderr': function('s:NvimOutputWrapper', [opts.err_cb]),
                    \ 'on_exit': function('s:NvimExitWrapper', [opts.exit_cb])
                    \ }
        if opts.hidden
            let jobid = jobstart(cmd, extend({ 'pty': v:true }, cb_opts))
        else
            let jobid = termopen(cmd, cb_opts)
        endif

        if jobid <= 0
            return {}
        endif

        let pty_job_info = nvim_get_chan_info(jobid)
        let pty = pty_job_info['pty']
        let ptybuf = get(pty_job_info, 'buffer', -1)
    else
        let ptybuf = term_start(a:cmd, {
                    \ 'term_name': opts.term_name,
                    \ 'term_highlight': 'Normal',
                    \ 'vertical': opts.vertical,
                    \ 'out_cb': opts.out_cb,
                    \ 'err_cb': opts.err_cb,
                    \ 'exit_cb': opts.exit_cb,
                    \ 'in_io': 'pipe',
                    \ 'hidden': opts.hidden,
                    \ 'term_finish': opts.term_finish,
                    \ 'curwin': !opts.hidden
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
endfunction " }}}
" mw#term#SendKeys: {{{
function! mw#term#SendKeys(job, str)
    if has('nvim')
        call chansend(a:job['jobid'], a:str)
    else
        call term_sendkeys(a:job['buffer'], a:str)
    endif
endfunction " }}}
" mw#term#Exited: return whether process has exited {{{
function! mw#term#Exited(job)
    if has('nvim')
        return nvim_get_chan_info(a:job['jobid']) == {}
    else
        let proc = term_getjob(a:job['buffer'])
        return proc == v:null || job_status(proc) !=# 'run'
    endif
endfunction " }}}
" mw#term#GetLine: scrape terminal line {{{
func! mw#term#GetLine(job, lnum)
    let bufid = a:job['buffer']
    if has('nvim')
        return get(getbufline(bufid, a:lnum), 0, '')
    else
        return term_getline(bufid, a:lnum)
    endif
endfunction " }}}
" s:NvimOutputWrapper: compatibility wrapper for neovim output/err callbacks {{{
function! s:NvimOutputWrapper(FuncRefObj, chan_id, msgs, name)
    call a:FuncRefObj(a:chan_id, join(a:msgs, ''))
endfunction " }}}
" s:NvimExitWrapper: compatibility wrapper for neovim exit callback {{{
function! s:NvimExitWrapper(FuncRefObj, job_id, exit_code, event_type)
    call a:FuncRefObj(a:job_id, a:exit_code)
endfunction " }}}
" s:DoNothing: do nothing function {{{
function! s:DoNothing(...)
endfunction " }}}
