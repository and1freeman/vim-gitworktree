let s:worktrees = []
let s:window = {
      \ 'is_open': 0,
      \ 'bufnr': -1,
      \ }


function! s:create_worktree_dict(_, git_output) abort
  let [path, commit, branch] = filter(split(a:git_output, ' '), {_, value -> !empty(value)})

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
  let s:window.bufnr = -1
endfunction


function! s:jump_to_window(winnr) abort
  exec 'silent ' . a:winnr . 'wincmd w'
endfunction


function! s:create_window() abort
  exec 'silent new [gitworktree]'

  setlocal buftype=nofile
  setlocal filetype=gitworktree
  setlocal bufhidden=wipe
  setlocal nobuflisted
  setlocal noswapfile

  return bufnr('%')
endfunction


function! s:fill_window(lines) abort
  setlocal modifiable
  silent normal! ggdG

  call append(0, a:lines)

  silent normal! Gddgg
  setlocal nomodifiable
endfunction


function! s:load_worktree() abort
  let cwd = getcwd()

  let buffers_in_current_worktree = filter(getbufinfo({ 'buflisted' : 1 }), {_, buf -> s:is_file_inside_path(buf.name, cwd)})
  let modified_buffers = filter(deepcopy(buffers_in_current_worktree), {_, buf -> buf.changed ==# 1 })
  let modified_buffers_names = map(deepcopy(modified_buffers), {_, buf -> fnamemodify(buf.name, ':t')})

  if len(modified_buffers) ># 0
    echohl ErrorMsg
    echoerr "Can not change worktree: following files are not saved:"
    echohl None

    echo join(modified_buffers_names, '\n')

    return
  endif

  let current_worktree = {}

  for tree in s:worktrees
    if tree.path ==# cwd
      let current_worktree = tree
    endif
  endfor

  let new_worktree = s:worktrees[line('.') - 1]

  if current_worktree.path ==# new_worktree.path
    echohl ErrorMsg
    echo "Already in " . current_worktree.path
    echohl None

    return
  endif

  for buffer in buffers_in_current_worktree
    exec ':bd ' . buffer.bufnr
  endfor

  let winnr = bufwinnr(s:window.bufnr)

  exec ':cd ' . new_worktree.path . ' | e ' . new_worktree.path
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

  let items = map(systemlist('git worktree list'), function('s:create_worktree_dict'))
  let s:worktrees = deepcopy(items)
  let entries = map(deepcopy(items), {key, val -> val.entry})
  let win_height = max([len(entries) + 2, 5])

  if s:window.is_open
    call s:jump_to_window(bufwinnr(s:window.bufnr))
  else
    let s:window.bufnr = s:create_window()
  endif

  exec 'wincmd J | resize ' . win_height

  let s:window.is_open = 1

  call s:fill_window(entries)
endfunction


augroup detect_gitworktree_filetype
autocmd!
autocmd Filetype gitworktree
      \ nnoremap <buffer> <cr> :call <sid>load_worktree()<cr>

autocmd Filetype gitworktree
      \ autocmd BufUnload <buffer>
      \ :call s:set_window_closed()
augroup END
