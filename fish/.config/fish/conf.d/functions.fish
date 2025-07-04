function whats_my_ip
    dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}'
end

# alias for downloading run.sh
functions --erase runsh
function runsh
    [ -d .vscode ] || mkdir .vscode
    [ -f .vscode/run.sh ] && mv .vscode/run.sh .vscode/run.sh~
    curl https://raw.githubusercontent.com/lczyk/run_sh/master/run.sh >.vscode/run.sh && chmod u+x .vscode/run.sh
end

function test_microphone
    arecord -vvv -f dat /dev/null
end
