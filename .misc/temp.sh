# find the most recent commit where given file existed

NEEDLE="06-keybinds.conf"
REV_LIST=$(git rev-list --all)
for REV in $REV_LIST; do
    # list all files in the commit
    echo "Checking commit $REV for file $NEEDLE"
    HAYSTACK=$(git ls-tree --name-only -r $REV)
    if echo "$HAYSTACK" | grep -q "$NEEDLE"; then
        echo "Found $NEEDLE in commit $REV"
        # show the commit details
        git show $REV -- $NEEDLE
        git checkout $REV
        echo "$HAYSTACK"
        break
    fi
done

