# OXware Hypervisor environment
export OXWARE_HYPERVISOR=1
export OXWARE_VERSION="2.7.0"

# Only modify PS1 for interactive shells
if [ -n "$PS1" ] && [ "$TERM" != "dumb" ]; then
    # Subtle OXware prefix on root shell prompt
    if [ "$EUID" -eq 0 ]; then
        export PS1='\[\033[1;31m\][OX]\[\033[0m\] \u@\h:\w# '
    fi
fi

# Aliases
alias ox='oxware-version'
alias oxware-status='systemctl status oxware --no-pager'
alias oxware-logs='journalctl -u oxware -f'
alias oxware-repair='sudo bash /opt/oxware/repair.sh'
