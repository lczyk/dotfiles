# Usage of spread:
#   -abend
#     	Stop without restoring on first error
#   -artifacts string
#     	Where to store task artifacts
#   -debug
#     	Run shell after script errors
#   -discard
#     	Discard reused servers without running
#   -gc
#     	Garbage collect backend resources when possible
#   -list
#     	Just show list of jobs that would run
#   -pass string
#     	Server password to use, defaults to random
#   -repeat int
#     	Number of times to repeat each task
#   -resend
#     	Resend project content to reused servers
#   -restore
#     	Run only the restore scripts
#   -reuse
#     	Keep servers running for reuse
#   -reuse-pid int
#     	Reuse servers from crashed process
#   -seed int
#     	Seed for job order permutation
#   -shell
#     	Run shell instead of task scripts
#   -shell-after
#     	Run shell after task scripts
#   -shell-before
#     	Run shell before task scripts
#   -v	Show detailed progress information
#   -vv
#     	Show debugging messages as well


if type -q spread
    # we don't have nice completions coming from spread
    # itself, do we make our own.
    # these are completions for the most common flags only
    # these are fish completions
    # note that the flags are a bit weird and have only single dashes
    complete --command spread --old-option reuse --description "Keep servers running"
    complete --command spread --old-option resend --description "Resend project content to reused servers"
    complete --command spread --old-option list --description "Just show list of jobs that would run"
    complete --command spread --old-option help --description "Show help message and exit"
    complete --command spread --old-option v --description "Show detailed progress information"
    complete --command spread --old-option vv --description "Show debugging messages as well"
end
