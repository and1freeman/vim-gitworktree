command! -nargs=* -complete=customlist,gitworktree#complete Gworktree
      \ call gitworktree#call(<q-args>)

nnoremap <leader>gw :Gworktree<cr>
