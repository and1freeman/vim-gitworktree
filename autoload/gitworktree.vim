let s:worktrees = []
let s:window = {
      \ 'is_open': 0,
      \ 'buf_id': -1,
      \ }


function! s:create_worktree_dict(_, git_output) abort
  let [path, commit, branch] = filter(split(a:git_output, ' '), {_, value ->
        \ !empty(value)}
        \ )

  let worktree = {
        \ 'path': path,
        \ 'commit': commit,
        \ 'branch': branch,
        \ 'entry': a:git_output
        \ }

  return worktree
endfunction


function! s:is_file_inside_path(filename, path) abort
  return len(matchstr(fnamemodify(a:filename, ':p'), a:path)) ># 0
endfunction


function! s:set_window_closed() abort
  let s:window.is_open = 0
  let s:window.buf_id = -1
endfunction


function! s:create_window(lines) abort
  let win_height = len(a:lines) + 2

  if s:window.buf_id ># 0
    exec 'silent ' . bufwinnr(s:window.buf_id) . 'wincmd w | resize ' win_height
  else
    exec 'silent ' . win_height . 'new [gitworktree]'

    setlocal buftype=nofile
    setlocal filetype=gitworktree
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal noswapfile
  endif


  setlocal modifiable
  silent norm! ggdG

  call append(0, a:lines)

  exec '$delete | norm gg'

  setlocal nomodifiable

  return bufnr('%')
endfunction


function! s:load_worktree() abort
  let cwd = getcwd()

  let modified_buffers = filter(
        \ getbufinfo({ 'bufmodified': 1, 'buflisted' : 1 }), {_, buf ->
        \ s:is_file_inside_path(buf.name, cwd)}
        \ )

  let modified_buffers_names = map(
        \ modified_buffers, {_, buf ->
        \ fnamemodify(buf.name, ':t')}
        \ )


  if len(modified_buffers) ># 0
    echohl ErrorMsg
    echo "Can not change worktree: following files are not saved:"
    echohl None

    echo join(modified_buffers_names, '\n')

    return
  endif

  let worktree = s:worktrees[line('.') - 1]

  exec '%bd | e ' . worktree.path
endfunction


function! gitworktree#list()
  let not_a_worktree = empty(trim(system('git rev-parse --is-inside-work-tree 2>/dev/null')))

  let cwd = getcwd()

  if not_a_worktree
    echohl ErrorMsg
    echom "git worktree not found: " . cwd
    echohl None
    return
  endif

  let items = map(systemlist('git worktree list'),
        \ function('s:create_worktree_dict'))

  let s:worktrees = deepcopy(items)

  let entries = map(deepcopy(items), {key, val -> val.entry})

  let s:window.is_open = 1
  let s:window.buf_id = s:create_window(entries)
endfunction


augroup detect_gitworktree_filetype
autocmd!
autocmd Filetype gitworktree
      \ nnoremap <buffer> <cr> :call <sid>load_worktree()<cr>

autocmd Filetype gitworktree
      \ autocmd BufUnload <buffer>
      \ :call s:set_window_closed()
augroup END
