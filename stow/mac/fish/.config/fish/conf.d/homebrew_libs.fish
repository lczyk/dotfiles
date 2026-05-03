# mac-only: expose homebrew include/lib dirs to compilers + dynamic linker.
if test -d /opt/homebrew/include
    set -gx CPATH /opt/homebrew/include $CPATH
end
if test -d /opt/homebrew/lib
    set -gx LIBRARY_PATH /opt/homebrew/lib $LIBRARY_PATH
    set -gx DYLD_LIBRARY_PATH /opt/homebrew/lib $DYLD_LIBRARY_PATH
end
