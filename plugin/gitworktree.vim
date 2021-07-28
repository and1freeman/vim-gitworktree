command! -nargs=0 Gworktree
      \ call gitworktree#list()

nnoremap <leader>gw :Gworktree<cr>
