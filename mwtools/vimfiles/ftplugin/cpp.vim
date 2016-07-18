let s:path = expand('<sfile>:p:h')

runtime compiler/cpp.vim

let c_no_curly_error = 1

exec 'source '.s:path.'/c.vim'

" vim: fdm=marker
