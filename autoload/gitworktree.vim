let s:worktrees = []
let s:window = {
      \ 'is_open': 0,
      \ 'bufnr': -1,
      \ }
let s:base = ''


function! s:update_worktrees_list() abort
  try
    let worktrees = map(systemlist('git worktree list'), function('s:create_worktree_obj'))
  catch
    let worktrees = []
  endtry

  let s:worktrees = deepcopy(worktrees)
  return worktrees
endfunction


function! s:create_worktree_obj(_, git_output) abort
  let [path, commit, branch] = filter(split(a:git_output, ' '), {_, value -> !empty(value)})
  let cwd = getcwd()

  let worktree = {
        \ 'path': path,
        \ 'commit': commit,
        \ 'branch': trim(branch, '[]'),
        \ 'is_current': path ==# cwd
        \ }

  return worktree
endfunction


function! s:show_warning(msg) abort
  echohl WarningMsg
  echo 'vim-gitworktree: ' . a:msg
  echohl None
endfunction


function! s:is_file_inside_path(filename, path) abort
  if !len(a:filename)
    return 0
  endif

  let modified = fnamemodify(a:filename, ':p')
  return filereadable(modified) && len(matchstr(modified, a:path)) > 0
endfunction


function! s:set_window_closed() abort
  let s:window.is_open = 0
  let s:window.bufnr = -1
endfunction


function! s:jump_to_window(winnr) abort
  exec 'silent ' . a:winnr . 'wincmd w'
endfunction


function! s:create_window() abort
  exec 'silent new'

  setlocal buftype=nofile
  setlocal filetype=gitworktree
  setlocal bufhidden=wipe
  setlocal nobuflisted
  setlocal noswapfile

  return bufnr('%')
endfunction


function! s:fill_window(winnr, lines) abort
  exec 'silent ' . a:winnr . 'wincmd w'

  setlocal modifiable
  silent normal! ggdG

  call append(0, a:lines)

  silent normal! Gddgg
  setlocal nomodifiable
endfunction


function! s:find(predicate, list, ...) abort
  let item = len(a:000) ? a:000[0] : 0

  for el in a:list
    if call(a:predicate, [el])
      let item = el
      break
    endif
  endfor

  return item
endfunction


function! s:load_worktree(path) abort
  silent call s:update_worktrees_list()

  let cwd = getcwd()

  let buffers_in_current_worktree = filter(getbufinfo({ 'buflisted' : 1 }), {_, buf -> s:is_file_inside_path(get(buf, 'name', ''), cwd)})
  let modified_buffers = filter(deepcopy(buffers_in_current_worktree), {_, buf -> get(buf, 'changed', 0) == 1 })
  let modified_buffers_names = map(deepcopy(modified_buffers), {_, buf -> fnamemodify(get(buf, 'name', ''), ':t')})


  if len(modified_buffers) > 0
    call s:show_warning("Can not change worktree. Following files are not saved:")
    echo join(modified_buffers_names, '\n')

    return
  endif

  let current_worktree = s:find({wtree -> get(wtree, 'is_current', 0)}, s:worktrees, {})
  let new_worktree = s:find({wtree -> get(wtree, 'path', '') ==# a:path}, s:worktrees, {})

  if empty(new_worktree)
    call s:show_warning('Can not find selected path. Try to update worktrees list.')
    return
  endif

  if get(current_worktree, 'path', 'NO_CURRENT') ==# get(new_worktree, 'path', 'NO_NEW')
    call s:show_warning("Already in " . current_worktree.path)
    return
  endif

  for buffer in buffers_in_current_worktree
    exec ':bd ' . buffer.bufnr
  endfor

  let winnr = bufwinnr(s:window.bufnr)

  let new_worktree_path = get(new_worktree, 'path')
  exec ':cd ' . new_worktree_path . ' | e ' . new_worktree_path
endfunction


function! s:is_worktree() abort
  let is_worktree = !empty(trim(system('git rev-parse --is-inside-work-tree 2>/dev/null')))

  if !is_worktree
    let cwd = getcwd()

    call s:show_warning('Not a git repository: ' . getcwd())
  endif

  return is_worktree
endfunction


function! s:flatten_list(list) abort
  let val = []

  for elem in a:list
    if type(elem) == type([])
      call extend(val, s:flatten_list(elem))
    else
      call extend(val, [elem])
    endif
    unlet elem
  endfor

  return val
endfunction



function! s:Exec() abort
  silent call s:update_worktrees_list()

  if !len(s:worktrees)
    call s:show_warning('Not a git repository: ' . getcwd())
    return
  endif

  let line = getline('.')
  let linenr = line('.')

  if !len(line)
    return
  endif

  let worktrees_start = search('\[Worktrees\]', 'n')
  let branches_start = search('\[Branches\]', 'n')
  let scope = linenr > branches_start
        \ ? 'branches'
        \ : linenr > worktrees_start && linenr != branches_start
        \ ? 'worktrees'
        \ : 'none'

  if scope ==# 'none'
    return
  endif


  if scope ==# 'worktrees'
    let worktree_path = substitute(trim(get(filter(split(line, ' '), {_, str -> match(str, '^/\f\+$') == 0 }), 0, ''), ' '), '[\/]$', '', '')

    if len(worktree_path) == 0
      return
    endif

    call s:load_worktree(worktree_path)

  elseif scope ==# 'branches'
    let branch_name = trim(line, '* ')
    echo branch_name
  endif

  silent call s:update_worktrees_list()
endfunction



function! gitworktree#call(...) abort
  if !s:is_worktree()
    return
  endif

  silent let worktrees_objs = s:update_worktrees_list()

  echo split(system('git rev-parse --git-dir'), '\n')
  let max_wtree_path_len = max(map(deepcopy(worktrees_objs), {_, wtree -> len(wtree.path)}))

  let worktrees = map(deepcopy(worktrees_objs), {_, wtree -> (wtree.is_current ? '* ' : '  ') . wtree.path . repeat(' ', max_wtree_path_len - len(wtree.path)) . '  ->  ' . wtree.branch})
  let branches = map(systemlist('git branch --list'), {_, branch -> (len(matchstr(branch, '*')) ==# 1 ? '* ' : '  ') . trim(branch, '*+ ')})

  let content = s:flatten_list([
        \ 'New worktrees will be created in ' . s:base,
        \ '',
        \ '[Worktrees]:',
        \  worktrees,
        \  '',
        \  '',
        \  '[Branches]:',
        \  branches
        \ ])

  if !s:window.is_open
    let s:window.bufnr = s:create_window()
  endif

  let winnr = bufwinnr(s:window.bufnr)
  let s:window.is_open = 1

  call s:jump_to_window(winnr)
  call s:fill_window(winnr, content)

  exec 'wincmd J'
endfunction


function! gitworktree#complete(lead, line, pos) abort
  return ['add', 'remove']
endfunction


function! s:get_branches() abort
  return map(split(system('git branch --list'), '\n'), {_, value -> trim(value, ' *')})
endfunction


function! s:get_current_branch() abort
  return trim(system('git branch --show-current'))
endfunction


augroup detect_gitworktree_filetype
  autocmd!
  autocmd Filetype gitworktree
        \ nnoremap <silent><buffer> <cr> :call <sid>Exec()<cr>

  autocmd Filetype gitworktree
        \ autocmd BufUnload <buffer> call <sid>set_window_closed()
augroup END
