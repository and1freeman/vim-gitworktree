if exists('g:loaded_gitworktree')
  finish
endif

let g:loaded_gitworktree = 1

command! -nargs=* -complete=customlist,gitworktree#complete Gwt
      \ call gitworktree#Call(<q-args>)

nnoremap <leader>gw :Gwt<cr>
