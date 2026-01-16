# on macos add code to path
if test -d "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
    export PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
end

if type -q code
    alias cr='code --reuse-window .'
end


if type -q zed
    alias zr='zed --reuse .'
end