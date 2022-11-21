" mw#coverage#OpenCovReport: {{{
" Description: 
function! mw#coverage#OpenCovReport()
    let filename = expand('%:p')

    if !mw#utils#IsInSandbox(filename)
        echohl ErrorMsg
        echomsg "Current file is not in a sandbox"
        echohl None
        return
    endif

    let anchordir = mw#utils#GetRootDir()

    let relpath = strpart(filename, strlen(anchordir)+1)
    let dirname = fnamemodify(relpath, ':h')
    let filename = fnamemodify(relpath, ':t:r')
    let fileext = fnamemodify(relpath, ':t:e')
    if fileext == 'm'
        let lang = 'MATLAB'
        " Weirdly the coverage report wants different paths for MATLAB vs.
        " C++ files
        let dirname = strpart(dirname, strlen('matlab/'))
    else
        let lang = 'C'
    endif

    let url_format = 'https://codecov-ws-02.mathworks.com/devel/Bcoretesttools/perfect/matlab/test/tools/metrics/codecoverage/report/html/detailView.html?cluster=Bstateflow&product=stateflow&language=%s&view=compDirFileDetail&dir=%s&basename=%s&ext=%s'

    let url = printf(url_format, lang, dirname, filename, fileext)
    let cmd = "x-www-browser '".url."'"
    call system(cmd)
endfunction " }}}
