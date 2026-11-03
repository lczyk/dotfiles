# Usage

Pipe lines into the limiter and it passes through at most `--limit` of them per window:

```sh
tail -f access.log | python cli.py --limit 10 --window 60
```

## Options

- `--limit N`: Maximum number of lines passed per window. Defaults to 10.
- `--window SECONDS`: Length of the window in seconds. Defaults to 60.
