" https://thoughtbot.com/blog/vim-splits-move-faster-and-more-naturally
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>
set splitbelow
set splitright

noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>

set number
filetype plugin on

nnoremap <Leader>d :FindDefinition<CR>  
vnoremap <Leader>d "ay:FindDefinition <C-R>a<CR> 

if exists('+termguicolors')
  let &t_8f="\<Esc>[38;2;%lu;%lu;%lum"
  let &t_8b="\<Esc>[48;2;%lu;%lu;%lum"
  set termguicolors
endif

" Theme
syntax enable
set background=dark
colorscheme ayu

let g:lightline = {
      \ 'active': {
      \   'left': [ [ 'mode', 'paste' ],
      \             [ 'gitbranch', 'readonly', 'filename', 'modified' ] ]
      \ },
      \ 'component': {'helloworld': 'Hello, world!'},
      \ 'component_function': {
      \   'gitbranch': 'FugitiveHead'
      \ },
      \ }

set noshowmode " lightline shows mode

" Auto-start NERDTree
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif
" https://stackoverflow.com/a/40197334/96531
" Refresh NERDTree without switching windows
nmap <Leader>r :NERDTreeFocus<cr>R<c-w><c-p>

nmap <c-p> :FZF<cr>
nmap <c-s> :w<cr>

imap <Tab> <C-P>

inoremap kj <Esc>

" https://www.freecodecamp.org/news/how-to-search-project-wide-vim-ripgrep-ack/
" ack.vim --- {{{

" Use ripgrep for searching ⚡️
" Options include:
" --vimgrep -> Needed to parse the rg response properly for ack.vim
" --type-not sql -> Avoid huge sql file dumps as it slows down the search
" --smart-case -> Search case insensitive if all lowercase pattern, Search case sensitively otherwise
let g:ackprg = 'rg --vimgrep --type-not csv --smart-case --context 2'

" Auto close the Quickfix list after pressing '<enter>' on a list item
let g:ack_autoclose = 1

" Any empty ack search will search for the work the cursor is on
let g:ack_use_cword_for_empty_search = 1

" Don't jump to first match
cnoreabbrev Ack Ack!

" Maps <leader>/ so we're ready to type the search keyword
nnoremap <Leader>/ :Ack!<Space>
" }}}

" Navigate quickfix list with ease
nnoremap <silent> [q :cprevious<CR>
nnoremap <silent> ]q :cnext<CR>

" https://stackoverflow.com/a/60907457/96531
map <C-y> :w !xclip -sel c <CR><CR>

" polyglot
let g:polyglot_disabled = ['elm'] " Zaptic/elm-vim covers this better

" ALE
let g:ale_fix_on_save = 1

