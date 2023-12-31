" ==============================================================================
" A common place for all the utility scripts. The actual body lies in the
" autoload/ directory.
" ============================================================================== 

command! -nargs=1 -complete=dir DWithOther          :call mw#sbtools#DiffWithOther(<f-args>)
command! -nargs=1 -complete=dir MWDiffWithOther     :call mw#sbtools#DiffWithOther(<f-args>)
command! -nargs=0               MWDiffWithArchive   :DWithOther archive
command! -nargs=0               MWDiffWithLKG       :DWithOther lkg
command! -nargs=1 -complete=dir SWithOther          :call mw#sbtools#SplitWithOther(<f-args>)
command! -nargs=1 -complete=dir MWSplitWithOther    :call mw#sbtools#SplitWithOther(<f-args>)
command! -nargs=1 -complete=dir DiffSandbox1        :call mw#sbtools#DiffWriteable1(<f-args>)
command! -nargs=+ -complete=dir DiffSandbox2        :call mw#sbtools#DiffWriteable2(<f-args>)
command! -nargs=* -complete=file DiffSubmitFile     :call mw#sbtools#DiffSubmitFile(<f-args>)
command! -nargs=0 -range AddHeaderProtection        :call mw#addHeaderProtection#DoIt()
command! -nargs=0 MWOpenCoverageReport              :call mw#coverage#OpenCovReport()


"command! -nargs=0 InitCppCompletion                 :call cpp_omni#Init()

com! -nargs=1 -bang -complete=customlist,mw#sbtools#EditFileCompleteFunc
       \ EditFile call mw#sbtools#EditFileUsingLocate(<q-args>)

com! -nargs=0 MWOpenFile call mw#open#OpenFile()

" At Mathworks, its usual practice to track modifications by figuring out
" which files are write-able. Therefore, vim's behavior of retaining the
" readonly-ness of files even after writing content to it hides changes we
" might have made.
augroup MakeWritableAndAddToPerforce
    au!
    au BufWritePre  * call mw#perforce#MakeWritable(expand('<afile>:p'))
    " adding a file to perforce needs to happen after write, not before
    " otherwise new files will not be added since they do not exist on disk
    " yet.
    au BufWritePost * call mw#perforce#AddFileToPerforce(expand('<afile>:p'))
augroup END

augroup AddSandboxTags
    au!
    au BufReadPost * call mw#tag#AddSandboxTags(expand('<afile>:p'))
augroup END

" Update tags in background after every write for the current project.
augroup MWRefreshProjectTags
    au!
    au BufWritePost * 
        \ : if has('unix') == 1 
        \ |     exec 'silent! !genVimTags.py '.expand('%:p:h').' &> /dev/null &'
        \ |     TlistUpdate
        \ | endif
augroup END

" Include this in your filetype.vim
augroup filetype
        au BufNewFile,BufRead *.tlc                     setf tlc
        au BufNewFile,BufRead *.rtw                     setf rtw
        au BufNewFile,BufRead *.cdr                     setf matlab
        au BufNewFile,BufRead *.zml                     setf zml
augroup END


command! -nargs=0 MWOpenFile :call mw#open#OpenFile()
if !hasmapto('mw#open#OpenFile')
    map <F4> :call mw#open#OpenFile()<CR>
endif

command! -nargs=? MWFindInProject               :call mw#sbtools#FindInProj(<f-args>)
command! -nargs=? MWFindInSolution              :call mw#sbtools#FindInSolution(<f-args>)

command! -nargs=0 MWCompileProject              :call mw#sbtools#CompileProject()
command! -nargs=0 MWCompileFile                 :call mw#sbtools#CompileFile()

command! -nargs=0 MWInitVimTags :call mw#tag#InitVimTags()

command! -nargs=0 MWSetProjectCompileLevel :call mw#sbtools#SetCompileLevelForProject()
command! -nargs=0 MWSetFileCompileLevel    :call mw#sbtools#SetCompileLevelForFile()

if !has('gui_running') && !has('nvim')
    finish
endif

amenu &Mathworks.D&iff.With\ &Sandbox                               :DWithOther<CR> 
amenu &Mathworks.D&iff.With\ S&YncFrom                              :DWithOther archive<CR>
amenu &Mathworks.D&iff.With\ &LKG                                   :DWithOther lkg<CR>
" amenu &Mathworks.D&iff.Using\ submit\ &file                         :DiffSubmitFile archive<CR>
" amenu &Mathworks.&Add\ current\ file\ to\ submit\ list              :!add.py %:p<CR>

amenu &Mathworks.-sep1- <Nop>
amenu &Mathworks.&Edit/Refactor.Add\ &header\ protection       :MWAddHeaderProtection<CR>
nmenu &Mathworks.&Edit/Refactor.&Indent\ file :call mw#edit#FormatCurrentSelection()<CR>
nmenu &Mathworks.&Edit/Refactor.-sep1- <Nop>
nmenu &Mathworks.&Edit/Refactor.&Rename\ symbol :call mw#refactor#rename()<CR>

amenu &Mathworks.-sep2- <Nop>
amenu &Mathworks.&Tags.&Initialize\ tags                    :MWInitVimTags<CR>
amenu &Mathworks.&Tags.Search\ through\ &Project\ tags      :call mw#tag#SelectTag(expand('%:p'))<CR>
amenu &Mathworks.&Tags.Search\ through\ &File\ tags         :call mw#tag#SelectTag(expand('%:p'))<CR>
command! -nargs=0 MWAddIncludeForSymbol  :call mw#tag#AddInclude()
amenu &Mathworks.&Tags.&Add\ include\ for\ current\ symbol  :MWAddIncludeForSymbol<CR>

nmenu &Mathworks.&Find.In\ &Project                 :call mw#sbtools#FindInProj()<CR>
nmenu &Mathworks.&Find.In\ &Solution                :call mw#sbtools#FindInSolution()<CR>
nmenu &Mathworks.&Find.Using\ sb&id                 :call mw#sbtools#FindUsingSbid()<CR>
nmenu &Mathworks.&Find.Using\ sb&global             :call mw#sbtools#FindUsingSbglobal()<CR>
nmenu &Mathworks.O&Pen\ file\ in\ project<Tab><F4>  :call mw#open#OpenFile()<CR>

amenu &Mathworks.-sep3- <Nop>
amenu &Mathworks.&Compile\ Current\ Project     :call mw#sbtools#CompileProject()<CR>
amenu &Mathworks.C&ompile\ Current\ File        :call mw#sbtools#CompileFile()<CR>
amenu &Mathworks.&Set\ Compile\ Level.For\ &Project           :call mw#sbtools#SetCompileLevelForProject()<CR>
amenu &Mathworks.&Set\ Compile\ Level.For\ &File              :call mw#sbtools#SetCompileLevelForFile()<CR>

amenu &Mathworks.-sep4- <Nop>
amenu &Mathworks.Sa&ve\ Current\ Session        :call mw#sbtools#SaveSession()<CR>
amenu &Mathworks.&Load\ Saved\ Session          :call mw#sbtools#LoadSession()<CR>

amenu &Mathworks.-sep5- <Nop>
amenu &Mathworks.P&4V.&RealEdits                :call mw#perforce#RealEditsFile(expand('%:p'))<CR>
amenu &Mathworks.Open\ Co&verage\ Report         :MWOpenCoverageReport<CR>

if has('nvim')
    nnoremap <A-m> :lua require('mw.telescope').commands()<CR>
    nnoremap <A-g> :lua require('mw.telescope').gdb()<CR>
    nnoremap <F3> :lua require('mw.telescope').buffers({ sort_lastused = true, sort_mru = true })<CR>
endif

" vim: fdm=marker
