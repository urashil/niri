# system summary on new kitty windows (stays above the instant prompt)
if [[ -o interactive && $SHLVL -eq 1 && -n $KITTY_WINDOW_ID ]] && (( $+commands[fastfetch] )); then fastfetch; fi

# powerlevel10k instant prompt (must stay near the top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export PATH="$HOME/.local/bin:$PATH"
export EDITOR=${EDITOR:-nvim}
export PAGER=less

# history
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt hist_ignore_all_dups hist_ignore_space share_history inc_append_history extended_history

# options
setopt auto_cd auto_pushd pushd_ignore_dups interactive_comments no_beep extended_glob

# completion
fpath=(/usr/share/zsh/site-functions $fpath)
[[ -d /usr/share/zsh-completions ]] && fpath=(/usr/share/zsh-completions $fpath)
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then compinit; else compinit -C; fi
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# keys
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# aliases
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --git --group-directories-first'
  alias la='eza -a --icons --group-directories-first'
  alias tree='eza --tree --icons'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lah'
  alias la='ls -A'
fi
(( $+commands[bat] )) && { alias cat='bat --paging=never --theme=ansi'; export MANPAGER="sh -c 'col -bx | bat -l man -p --theme=ansi'"; }
(( $+commands[btop] )) && alias top=btop
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias wp='wallpaper next'

# fzf / zoxide (colors use the terminal palette, so they follow the wallpaper)
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border=rounded --color=fg:7,bg:-1,hl:4,fg+:15,bg+:0,hl+:12,info:3,prompt:16,pointer:16,marker:2,spinner:3,header:8,border:8'
(( $+commands[fd] )) && export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
for f in /usr/share/fzf/key-bindings.zsh /usr/share/fzf/completion.zsh; do [[ -r $f ]] && source $f; done
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"

# prompt
source ~/.local/share/zsh/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
[[ -f ~/.p10k-colors.zsh ]] && source ~/.p10k-colors.zsh

# plugins (autosuggestions first, syntax highlighting last)
for f in /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do [[ -r $f ]] && source $f; done
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
for f in /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do [[ -r $f ]] && source $f; done
