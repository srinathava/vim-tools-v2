command! -nargs=* MWDebugMATLAB             :call mw#gdb#StartMATLAB(1, <f-args>)
command! -nargs=1 MWDebugUnitTest           :call mw#gdb#UnitTests(<f-args>)
command! -nargs=0 MWDebugCurrentTestPoint   :call mw#gdb#CurrentTestPoint()

if has('gui')
    amenu &Mathworks.&Debug.&1\ MATLAB\ -nojvm          :call mw#gdb#StartMATLAB(1, '-nojvm')<CR>
    amenu &Mathworks.&Debug.&2\ MATLAB\ -nodesktop      :call mw#gdb#StartMATLAB(1, '-nodesktop -nosplash')<CR>
    amenu &Mathworks.&Debug.&3\ MATLAB\ desktop         :call mw#gdb#StartMATLAB(1, '-desktop')<CR>
    amenu &Mathworks.&Debug.&4\ MATLAB\ custom          :call mw#gdb#StartMATLABWithCustomCmdLineArgs(1)<CR>
    amenu &Mathworks.&Debug.&Attach\ to\ MATLAB         :call mw#gdb#AttachToMATLAB('MATLAB', '-nojvm')<CR>
    amenu &Mathworks.&Debug.&current\ unit/pkgtest   :call mw#gdb#UnitTests('current')<CR>
    amenu &Mathworks.&Debug.&unittest                :call mw#gdb#UnitTests('unit')<CR>
    amenu &Mathworks.&Debug.&pkgtest                 :call mw#gdb#UnitTests('pkg')<CR>
    amenu &Mathworks.&Debug.Current\ &Test\ Point     :call mw#gdb#CurrentTestPoint()<CR>

    amenu &Mathworks.&Run.&1\ MATLAB\ -nojvm        :call mw#gdb#StartMATLAB(0, '-nojvm')<CR>
    amenu &Mathworks.&Run.&2\ MATLAB\ -nodesktop    :call mw#gdb#StartMATLAB(0, '-nodesktop -nosplash')<CR>
    amenu &Mathworks.&Run.&3\ MATLAB\ desktop       :call mw#gdb#StartMATLAB(0, '-desktop')<CR>
    amenu &Mathworks.&Run.&4\ MATLAB\ custom        :call mw#gdb#StartMATLABWithCustomCmdLineArgs(0)<CR>
    amenu &Mathworks.&Run.&5\ MATLAB\ -check_malloc :call mw#gdb#StartMATLAB(0, '-check_malloc')<CR>
endif
