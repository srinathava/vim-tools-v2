" DoIt: adds header re-inclusion directives to the current file {{{
function! mw#addHeaderProtection#DoIt()
    let fname = expand('%:t:r')
    let dir = expand('%:p:h:t')

    call append(0, '#pragma once')
    let year = strftime('%Y')
    call append(0, '/* Copyright '.year.' The MathWorks, Inc. */')
endfunction " }}}
