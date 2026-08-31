function webfish --description 'serve this shell as a browser terminal on localhost, themed to match alacritty'
    if not type -q ttyd
        printf 'webfish: ttyd not found -- install it first\n' >&2
        return 1
    end

    set -l port 7681
    if set -q argv[1]
        set port $argv[1]
    end

    # bind loopback only -- ttyd's default is every interface, and this shell
    # has no auth of any kind.
    set -l iface lo
    if test (uname) = Darwin
        set iface lo0
    end

    set -l theme '{"background":"#1c1c1c","foreground":"#ddeedd","cursor":"#ddeedd","cursorAccent":"#1c1c1c","selectionBackground":"#554444","black":"#3d352a","red":"#cd5c5c","green":"#86af80","yellow":"#e8ae5b","blue":"#6495ed","magenta":"#deb887","cyan":"#b0c4de","white":"#bbaa99","brightBlack":"#554444","brightRed":"#cc5533","brightGreen":"#88aa22","brightYellow":"#ffa75d","brightBlue":"#87ceeb","brightMagenta":"#996600","brightCyan":"#b0c4de","brightWhite":"#ddccbb"}'

    printf 'webfish: http://localhost:%s\n' $port

    # -W because ttyd is read-only by default since 1.7.
    env COLORTERM=truecolor ttyd \
        -W -p $port -i $iface -T xterm-256color \
        -t 'fontFamily=UbuntuMono Nerd Font Mono, Ubuntu Mono, monospace' \
        -t fontSize=20 \
        -t lineHeight=1.0 \
        -t cursorStyle=block \
        -t cursorBlink=false \
        -t drawBoldTextInBrightColors=false \
        -t disableResizeOverlay=true \
        -t disableLeaveAlert=true \
        -t rendererType=webgl \
        -t titleFixed=fish \
        -t "theme=$theme" \
        fish -l
end
