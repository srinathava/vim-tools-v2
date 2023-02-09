command! -nargs=* MWDebugMATLAB             :call mw#gdb#StartMATLAB(1, <f-args>)
command! -nargs=1 MWDebugUnitTest           :call mw#gdb#UnitTests(<f-args>)
command! -nargs=0 MWDebugCurrentTestPoint   :call mw#gdb#CurrentTestPoint()
command! -nargs=0 MWRunMATLABLoadSL         :call mw#gdb#StartMATLAB('-desktop -r "open_system(new_system); bdclose all"')

if has('gui')
    amenu &Mathworks.&Debug.&current\ unit/pkgtest   :call mw#gdb#UnitTests('current')<CR>
    amenu &Mathworks.&Debug.&unittest                :call mw#gdb#UnitTests('unit')<CR>
    amenu &Mathworks.&Debug.&pkgtest                 :call mw#gdb#UnitTests('pkg')<CR>
    amenu &Mathworks.&Debug.Current\ &Test\ Point     :call mw#gdb#CurrentTestPoint()<CR>

    amenu &Mathworks.&Run.&1\ MATLAB\ desktop       :call mw#gdb#StartMATLAB('-desktop')<CR>
    amenu &Mathworks.&Run.&2\ MATLAB\ custom        :call mw#gdb#StartMATLABWithCustomCmdLineArgs()<CR>
    amenu &Mathworks.&Run.&3\ MATLAB\ (pre-load\ Simulink) :MWRunMATLABLoadSL<CR>
endif
