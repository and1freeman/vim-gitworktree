let s:worktrees = []
let s:window = {
      \ 'is_open': 0,
      \ 'bufnr': -1,
      \ }

let s:base = '../'


function! s:isWorktree() abort
  let isWorktree = !empty(trim(system('git rev-parse --is-inside-work-tree 2>/dev/null')))

  if !isWorktree
    call utils#EchoWarning('Not a git repository: ' . getcwd())
  endif

  return isWorktree
endfunction


function! s:UpdateWorktreesList() abort
  try
    let worktrees = map(systemlist('git worktree list'), function('s:CreateWorktreeObject'))
  catch
    let worktrees = []
  endtry

  let s:worktrees = deepcopy(worktrees)
  return worktrees
endfunction


function! s:CreateWorktreeObject(_, git_output) abort
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


function! s:isFileInsidePath(filename, path) abort
  if !len(a:filename)
    return 0
  endif

  let modified = fnamemodify(a:filename, ':p')
  return filereadable(modified) && len(matchstr(modified, a:path)) > 0
endfunction


function! s:SetWindowClosed() abort
  let s:window.is_open = 0
  let s:window.bufnr = -1
endfunction


function! s:CreateWindow() abort
  exec 'silent new'

  setlocal buftype=nofile
  setlocal filetype=gitworktree
  setlocal bufhidden=wipe
  setlocal nobuflisted
  setlocal noswapfile

  return bufnr('%')
endfunction


function! s:FillWindow(winnr, lines) abort
  exec 'silent ' . a:winnr . 'wincmd w'

  setlocal modifiable
  silent normal! ggdG

  call append(0, a:lines)

  silent normal! Gddgg
  setlocal nomodifiable
endfunction


function! s:LoadWorktree(path) abort
  silent call s:UpdateWorktreesList()

  if empty(a:path)
    return
  endif

  let cwd = getcwd()

  let buffers_in_current_worktree = filter(getbufinfo({ 'buflisted' : 1 }), {_, buf -> s:isFileInsidePath(get(buf, 'name', ''), cwd)})
  let modified_buffers = filter(deepcopy(buffers_in_current_worktree), {_, buf -> get(buf, 'changed', 0) == 1 })
  let modified_buffers_names = map(deepcopy(modified_buffers), {_, buf -> fnamemodify(get(buf, 'name', ''), ':.')})

  if len(modified_buffers)
    call utils#EchoWarning("Can not change worktree. Following files are not saved:")
    echo join(modified_buffers_names, '\n')

    return
  endif

  let current_worktree = utils#Find({wtree -> get(wtree, 'is_current', 0)}, s:worktrees, {})
  let new_worktree = utils#Find({wtree -> get(wtree, 'path', '') ==# a:path}, s:worktrees, {})

  if empty(new_worktree)
    call utils#EchoWarning('Can not find selected worktree. Try to update worktrees list.')
    return
  endif

  if get(current_worktree, 'path', 'NO_CURRENT') ==# get(new_worktree, 'path', 'NO_NEW')
    call utils#EchoWarning('Already in ' . current_worktree.path . '. ' .  '[' . current_worktree.branch . ']')
    return
  endif

  for buffer in buffers_in_current_worktree
    exec ':bd ' . get(buffer, 'bufnr', -1)
  endfor

  let new_worktree_path = get(new_worktree, 'path')
  exec ':cd ' . new_worktree_path . ' | e ' . new_worktree_path
endfunction

function! s:AddWorktree(branch) abort
  " TODO
  let path = '../' . a:branch
  let current_branch = trim(system('git branch --show-current'), " \n")

  if a:branch ==# current_branch
    call utils#EchoWarning('Already at [' . a:branch . '].')
    return
  elseif isdirectory(path)
    call utils#EchoWarning('Directory ' . path . ' already exists.')
    return
  endif
endfunction

function! s:remove_worktree() abort
  " TODO
  " check if worktrees have changed since status buffer creation as in s:LoadWorktree

  let data = s:GetContext()
  let wtpath = get(data, 'wtpath')

  if empty(wtpath)
    call utils#EchoWarning('Not a worktree.')
    return
  endif

  if !empty(matchstr(wtpath, ' --force '))
    return
  endif

  try
    let msg = get(systemlist('git worktree remove ' . shellescape(wtpath)), 0, '')
  catch
    echo 'error'
  endtry

  let is_main = !empty(matchstr(msg, 'is a main working tree'))
  let is_modified = !empty(matchstr(msg, 'contains modified or untracked'))

  if is_main
    call utils#EchoWarning("Can not remove worktree. \n" . wtpath . ' is a main worktree.')
  elseif is_modified
    call utils#EchoWarning("Can not remove worktree. \n" . wtpath . ' contains modified or untracked files.')
  else
    call gitworktree#Call()
  endif
endfunction


function! s:GetContext() abort
  silent call s:UpdateWorktreesList()

  let defaults = {
        \ 'line': '',
        \ 'context': '',
        \ 'wtpath': '',
        \ 'branch': ''
        \ }

  if empty(s:worktrees)
    call utils#EchoWarning('Not a git repository: ' . getcwd())
    return defaults
  endif

  let line = getline('.')
  let linenr = line('.')

  if empty(line)
    return defaults
  endif

  let worktrees_start = search('\[Worktrees\]', 'n')
  let branches_start = search('\[Branches\]', 'n')
  let context = linenr > branches_start
        \ ? 'branches'
        \ : linenr > worktrees_start && linenr != branches_start
        \ ? 'worktrees'
        \ : ''

  call extend(defaults, { 'context': context })

  if empty(context)
    return defaults
  elseif context ==# 'worktrees'
    let wtpath = substitute(trim(get(filter(split(line, ' '), {_, str -> match(str, '^/\f\+$') == 0 }), 0, ''), ' '), '[\/]$', '', '')
    call extend(defaults, { 'wtpath': wtpath })
  elseif context ==# 'branches'
    let branch = trim(line, '* ')
    call extend(defaults, { 'branch': branch })
  endif

  call extend(defaults, { 'line': line })

  return defaults
endfunction


function! s:OnEnter() abort
  let data = s:GetContext()

  let context = get(data, 'context')
  let wtpath = get(data, 'wtpath')
  let branch = get(data, 'branch')

  if context ==# 'worktrees'
    call s:LoadWorktree(wtpath)
  elseif context ==# 'branches'
    call s:AddWorktree(branch)
  endif

  silent call s:UpdateWorktreesList()
endfunction


function! gitworktree#Call(...) abort
  if !s:isWorktree()
    return
  endif

  silent let worktrees_objs = s:UpdateWorktreesList()
  let max_wtree_path_len = max(map(deepcopy(worktrees_objs), {_, wtree -> len(wtree.path)}))
  let worktrees = map(deepcopy(worktrees_objs), {_, wtree -> (wtree.is_current ? '* ' : '  ')
        \ . wtree.path
        \ . repeat(' ', max_wtree_path_len - len(wtree.path)) . '  ->  ' . wtree.branch})

  let branches = map(systemlist('git branch --list'), {_, branch -> (len(matchstr(branch, '*')) ==# 1 ? '* ' : '  ') . trim(branch, '*+ ')})

  let cwd = getcwd()
  let content = utils#FlattenList([
        \ 'Current working directory: ' . cwd,
        \ 'New worktrees will be created in ' . fnamemodify(cwd, ':h'),
        \ '',
        \ '[Worktrees]:',
        \  worktrees,
        \  '',
        \  '',
        \  '[Branches]:',
        \  branches
        \ ])

  if !s:window.is_open
    let s:window.bufnr = s:CreateWindow()
  endif

  let winnr = bufwinnr(s:window.bufnr)
  let s:window.is_open = 1

  call s:FillWindow(winnr, content)
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
        \ nnoremap <silent><buffer> <cr> :call <sid>OnEnter()<cr>

  autocmd Filetype gitworktree
        \ nnoremap <silent><buffer> gd :call <sid>remove_worktree()<cr>

  autocmd Filetype gitworktree
        \ autocmd BufUnload <buffer> call <sid>SetWindowClosed()
augroup END
