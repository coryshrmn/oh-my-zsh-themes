TS_ZSH_HOST=''
TS_ZSH_COLORIZED_HOST=''

TS_ZSH_WIDGETS=()

TS_ZSH_WIDGETS_UPDATE_FUNC=()
TS_ZSH_WIDGETS_UPDATE_MIN=()
TS_ZSH_WIDGETS_UPDATE_MAX=()
TS_ZSH_WIDGETS_UPDATE_LAST=()
TS_ZSH_WIDGETS_FILE=()

TS_ZSH_LOG_UPDATE=0

function current_time_ms()
{
    date +%s\ %N | awk '{printf("%.0f", $1 * 1000.0 + $2 / 1000000.0)}'
}


function ts_zsh_is_ssh()
{
    if [[ -n $SSH_CLIENT || -n $SSH_TTY ]]; then
        return 0
    else
        return 1
    fi
}

function ts_zsh_download_domains()
{
    local tsdir
    local sld
    local tld
    local domains
    tsdir="$ZSH/themes/terriblysimple"
    mkdir -p $tsdir
    sld="$tsdir/sld"
    tld="$tsdir/tld"
    domains="$tsdir/domains"

    curl -s 'https://raw.github.com/gavingmiller/second-level-domains/master/SLDs.csv' > $sld
    curl -s 'http://data.iana.org/TLD/tlds-alpha-by-domain.txt' > $tld
    sed -i -e '/^#/d' -e 's/^/./' -e 's/\(.*\)/\L\1/' $tld
    sed -i -e 's/^[^,]*,\.*\(.*\)/.\1/' -e 's///' $sld
    sort -u $sld $tld > $domains
    rm $sld
    rm $tld
}
if [[ ! -s "$ZSH/themes/terriblysimple/domains" ]]; then
    echo 'TS_ZSH downloading domains'
    ts_zsh_download_domains
fi

#input: string
#wraps color codes with the zsh %{%}
#so they aren't counted in width
function ts_zsh_esc()
{
    echo $1 | sed 's/\[[0-9;]*m/%{&%}/g'
}

#input: update_func update_min update_max
function ts_zsh_widget_add()
{
    integer i
    i=$(($#TS_ZSH_WIDGETS_UPDATE_FUNC + 1))
    TS_ZSH_WIDGETS_UPDATE_FUNC[$i]=$1;
    TS_ZSH_WIDGETS_UPDATE_MIN[$i]=$2;
    TS_ZSH_WIDGETS_UPDATE_MAX[$i]=$3;
    TS_ZSH_WIDGETS_UPDATE_LAST[$i]=0
    if (($+commands[mktemp])); then
        TS_ZSH_WIDGETS_FILE[$i]=`mktemp`
    else
        TS_ZSH_WIDGETS_FILE[$i]=`tempfile`
    fi
}

#input: update_func file_name
function ts_zsh_widgets_sync_update()
{
    local contents
    contents=$(ts_zsh_esc "$(eval $1 2>/dev/null)")
    echo $contents > $2
}

#input: update_func file_name
function ts_zsh_widgets_async_update()
{
    (ts_zsh_widgets_sync_update $@ &)
}

function ts_zsh_log_update
{
    if (($TS_ZSH_LOG_UPDATE)); then
        echo -n $1 >> ~/script/log.txt
    fi
}

function precmd()
{
    local hname
    hname=`hostname`
    if [[ $hname < $TS_ZSH_HOST || $hname > $TS_ZSH_HOST ]]; then
        #echo 'TS_ZSH recalculating hostname'
        TS_ZSH_HOST=$hname
        TS_ZSH_COLORIZED_HOST=$(ts_zsh_esc "$(ts_zsh_colorize_host_cache $hname)")
    fi

    TS_ZSH_INFO=
    integer currtime
    currtime=`current_time_ms`
    integer endi
    endi=$(($#TS_ZSH_WIDGETS_UPDATE_FUNC))
    if (($endi >= 1)); then
        for i in {1..$endi}; do
            #sync update
            if (($TS_ZSH_WIDGETS_UPDATE_MAX[$i] >= 0 && $currtime >= (($TS_ZSH_WIDGETS_UPDATE_LAST[$i] + $TS_ZSH_WIDGETS_UPDATE_MAX[$i]))))
            then
                TS_ZSH_WIDGETS_UPDATE_LAST[$i]=$currtime
                ts_zsh_log_update "$fg[red]|"
                ts_zsh_widgets_sync_update $TS_ZSH_WIDGETS_UPDATE_FUNC[$i] $TS_ZSH_WIDGETS_FILE[$i]
            #async update
            elif (($currtime >= (($TS_ZSH_WIDGETS_UPDATE_LAST[$i] + $TS_ZSH_WIDGETS_UPDATE_MIN[$i]))))
            then
                TS_ZSH_WIDGETS_UPDATE_LAST[$i]=$currtime
                ts_zsh_log_update "$fg[yellow]|"
                ts_zsh_widgets_async_update $TS_ZSH_WIDGETS_UPDATE_FUNC[$i] $TS_ZSH_WIDGETS_FILE[$i]
            else; ts_zsh_log_update "$fg[green]|"
            fi
            TS_ZSH_INFO=${TS_ZSH_INFO}`cat $TS_ZSH_WIDGETS_FILE[$i]`
        done
        ts_zsh_log_update "$reset_color\n"
    fi
}

function ts_zsh_is_tld()
{
    local hname
    hname=${1//./\\.}
    echo `grep -ixc '^'$hname'$' $ZSH/themes/terriblysimple/domains`
}

function ts_zsh_print_domain()
{
    echo -n "$1" | sed -e 's/\([^.]*\)$/[01;32m\1[00m/' -e 's/\([^.]*\)\./[01;36m\1[00m./g'
}

function ts_zsh_colorize_host_cache()
{
    integer endi
    endi=$(($#1))
    if (( $endi > 0 )) then;
        for i in {1..$endi}; do
            if (( $(ts_zsh_is_tld ${1[$i,-1]}) )); then
                ts_zsh_print_domain "${1[1, $i-1]}"
                echo -n ".\033[01;33m${1[$i+1,-1]}\033[00m"
                return
            else
            fi
        done
    fi
    ts_zsh_print_domain "$1"
}

#$fg[green]%B%M%b$reset_color "\
PROMPT=`ts_zsh_esc "$reset_color%(?..$bg[red]$fg[white]ERR: %B%?%b$reset_color
)\
%(!.$bg[red]$fg_bold[white].$fg[yellow])%B%n%b\
$reset_color$fg[$(if ts_zsh_is_ssh; then; echo red; else; echo blue; fi)]@"\
'$TS_ZSH_COLORIZED_HOST \
%{$fg[$(if [ -w "$(pwd)" ]; then; echo magenta; else; echo red; fi)]%}'\
"%B%~%b$reset_color "\
'$(git_prompt_info)'\
"$fg[green]%B%(!.#.>)%b$reset_color"`

RPROMPT='$TS_ZSH_INFO'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_no_bold[blue]%}[%{$fg_bold[yellow]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$fg_no_bold[blue]%}]%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_CLEAN=""
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg_bold[red]%}*"

# LS colors, made with http://geoff.greer.fm/lscolors/
export LSCOLORS="Gxfxcxdxbxegedabagacad"
export LS_COLORS='no=00:fi=00:di=01;34:ln=00;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=41;33;01:ex=00;32:*.cmd=00;32:*.exe=01;32:*.com=01;32:*.bat=01;32:*.btm=01;32:*.dll=01;32:*.tar=00;31:*.tbz=00;31:*.tgz=00;31:*.rpm=00;31:*.deb=00;31:*.arj=00;31:*.taz=00;31:*.lzh=00;31:*.lzma=00;31:*.zip=00;31:*.zoo=00;31:*.z=00;31:*.Z=00;31:*.gz=00;31:*.bz2=00;31:*.tb2=00;31:*.tz2=00;31:*.tbz2=00;31:*.avi=01;35:*.bmp=01;35:*.fli=01;35:*.gif=01;35:*.jpg=01;35:*.jpeg=01;35:*.mng=01;35:*.mov=01;35:*.mpg=01;35:*.pcx=01;35:*.pbm=01;35:*.pgm=01;35:*.png=01;35:*.ppm=01;35:*.tga=01;35:*.tif=01;35:*.xbm=01;35:*.xpm=01;35:*.dl=01;35:*.gl=01;35:*.wmv=01;35:*.aiff=00;32:*.au=00;32:*.mid=00;32:*.mp3=00;32:*.ogg=00;32:*.voc=00;32:*.wav=00;32:'
