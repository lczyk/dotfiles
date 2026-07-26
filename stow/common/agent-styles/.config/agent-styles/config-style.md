## config-file style

applies to `toml`, `yaml`, `json`, `ini`, and friends -- `pyproject.toml`, `tox.ini`, `package.json`, ci workflow files, and so on.

### lists

- **multi-item lists stay multiline** put each item on its own line. one-item-per-line keeps git diffs minimal (a line touched is a line changed) and makes it trivial to comment out / re-enable individual entries without rebalancing brackets or commas.
- **trailing `#` sentinel to lock multiline shape** end the list with a bare comment line before the closing bracket. this anchors the multiline form against autoformatters that would otherwise collapse a single-item list onto one line, and gives a stable place to drop a `# "FOO",` commented-out entry. e.g.

    ```toml
    dependencies = [
        "torch",
        "numpy",
        #
    ]
    ```

    apply consistently even to short lists -- the rule is "every list, every time", not "lists above N entries". write the sentinel as a bare `#` with nothing after it: `# ` with a trailing space is equivalent to a config parser, but the pre-commit hook rejects trailing whitespace on added lines.

- **inline `# what-it-is` after opaque short tokens** when list entries are terse codes whose meaning isn't obvious from the token alone (ruff/flake8 codes like `E` / `F` / `B` / `SIM`, mypy plugin names, ci job ids, etc.), append an inline comment naming what each token expands to. align the comments at a consistent column so the file scans as a two-column table. e.g.

    ```toml
    select = [
        "E",   # pycodestyle
        "F",   # pyflakes
        "B",   # flake8-bugbear
        "SIM", # flake8-simplify
        # "PL",  # pylint -- enable later
    ]
    ```

    skip the inline comment when the token is self-describing (a package name, a file path, a human-readable identifier). the rule kicks in only when the token is a code or shorthand a future reader would have to look up.
