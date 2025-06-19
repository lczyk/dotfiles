function logo -d "Draw a cute ascii fish"
    set -q red; or set -l red ff0000
    set -q grey; or set -l grey ffff00
    set -q yellow; or set -l yellow ff7f00

    if type -q __bobthefish_colors
        # Use repo colors for to color the fish
        __bobthefish_colors $theme_color_scheme
        set red $color_repo_dirty[1]
        set grey $color_repo_work_tree[1]
        set yellow $color_repo_staged[1]
    end

    type -q __bobthefish_glyphs; and __bobthefish_glyphs

#     echo '                '(set_color $red[1])'____
#   ___======____='(set_color $yellow[1])'-'(set_color $grey[1])'-'(set_color $yellow[1])'-='(set_color $red[1])')
# /T            \_'(set_color $grey[1])'--='(set_color $yellow[1])'=='(set_color $red[1])')
# [ \ '(set_color $yellow[1])'('(set_color $grey[1])'0'(set_color $yellow[1])')   '(set_color $red[1])'\~    \_'(set_color $grey[1])'-='(set_color $yellow[1])'='(set_color $red[1])')
#  \      / )J'(set_color $yellow[1])'~~    \\'(set_color $grey[1])'-='(set_color $red[1])')
#   \\\\___/  )JJ'(set_color $yellow[1])'~'(set_color $grey[1])'~~   '(set_color $red[1])'\)
#    \_____/JJJ'(set_color $yellow[1])'~~'(set_color $grey[1])'~~    '(set_color $red[1])'\\
#    '(set_color $yellow[1])'/ '(set_color $grey[1])'\  '(set_color $grey[1])', \\'(set_color $red[1])'J'(set_color $yellow[1])'~~~'(set_color $grey[1])'~~     '(set_color $yellow[1])'\\
#   (-'(set_color $grey[1])'\)'(set_color $red[1])'\='(set_color $yellow[1])'|'(set_color $grey[1])'\\\\\\'(set_color $yellow[1])'~~'(set_color $grey[1])'~~       '(set_color $yellow[1])'L_'(set_color $grey[1])'_
#   '(set_color $yellow[1])'('(set_color $red[1])'\\'(set_color $yellow[1])'\\)  ('(set_color $grey[1])'\\'(set_color $yellow[1])'\\\)'(set_color $red[1])'_           '(set_color $grey[1])'\=='(set_color $yellow[1])'__
#    '(set_color $red[1])'\V    '(set_color $yellow[1])'\\\\'(set_color $red[1])'\) =='(set_color $yellow[1])'=_____   '(set_color $grey[1])'\\\\\\\\'(set_color $yellow[1])'\\\\
#           '(set_color $red[1])'\V)     \_) '(set_color $yellow[1])'\\\\'(set_color $grey[1])'\\\\JJ\\'(set_color $yellow[1])'J\)
#                       '(set_color $red[1])'/'(set_color $yellow[1])'J'(set_color $grey[1])'\\'(set_color $yellow[1])'J'(set_color $red[1])'T\\'(set_color $yellow[1])'JJJ'(set_color $red[1])'J)
#                       (J'(set_color $yellow[1])'JJ'(set_color $red[1])'| \UUU)
#                        (UU)'(set_color normal)

    # Art by Linda Ball
    # https://www.asciiart.eu/animals/fish
    echo '                '(set_color $grey[1])'O  o
           '(set_color $yellow[1])'_'(set_color $red[1])'\\'(set_color $yellow[1])'_   '(set_color $grey[1])'o
 '(set_color $red[1])'>'(set_color $yellow[1])'('(set_color $grey[1])'\''(set_color $yellow[1])'\>  '(set_color $red[1])'\\\\'(set_color $yellow[1])'/  '(set_color $grey[1])'o'(set_color $yellow[1])'\\ '(set_color $grey[1])'.
        '(set_color $red[1])'//'(set_color $yellow[1])'\\___=
           '''(set_color normal)
end