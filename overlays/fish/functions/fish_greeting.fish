function fish_greeting
    if set -q PANDORA_DASHBOARD
        return
    end

    if set -q PANDORA_SHOW_GREETING; and test "$PANDORA_SHOW_GREETING" = 0
        return
    end

    command -v fastfetch &>/dev/null; and fastfetch
end
