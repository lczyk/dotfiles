# alias for downloading run.sh
functions --erase runsh
function runsh
    [ -d .vscode ] || mkdir .vscode
    [ -f .vscode/run.sh ] && mv .vscode/run.sh .vscode/run.sh~
    curl https://raw.githubusercontent.com/MarcinKonowalczyk/run_sh/master/run.sh >.vscode/run.sh && chmod u+x .vscode/run.sh
end
