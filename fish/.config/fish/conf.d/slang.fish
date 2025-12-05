# if $HOME/.slang/bin is a directory, add it to the PATH
if test -d "$HOME/.slang/bin"
	set -gx PATH "$HOME/.slang/bin" $PATH
end
