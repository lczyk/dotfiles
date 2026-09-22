---
name: caveman-compress
description: >
  compress natural-language memory files (CLAUDE.md, todos, preferences) into
  caveman format to save input tokens. preserves all technical substance, code,
  urls and structure. the compressed version overwrites the original; a
  human-readable backup goes out-of-tree under $XDG_DATA_HOME/caveman-compress/backups/.
  trigger: /caveman-compress FILEPATH or "compress memory file"
---

# caveman-compress

## purpose

compress natural-language files (CLAUDE.md, todos, preferences) into caveman-speak to cut input tokens. the compressed version overwrites the original. the human-readable backup is saved as `<filename>.original.md`, but not beside the source -- it lives out-of-tree in `$XDG_DATA_HOME/caveman-compress/backups/<parent-dir-name>/` (default `~/.local/share/...`), so skill auto-loaders don't re-ingest it as a live file.

any yaml frontmatter is split off before compression and re-prepended verbatim, so `name:` / `description:` blocks survive untouched.

## trigger

`/caveman-compress <filepath>`, or when the user asks to compress a memory file.

## process

1. this SKILL.md sits next to `scripts/`; find that directory.
2. run:

    ```
    cd <directory-containing-this-SKILL.md> && python3 -m scripts <absolute-filepath>
    ```

3. the cli:
    - detects the file type (no tokens)
    - calls claude to compress
    - validates the output (no tokens)
    - on errors, cherry-picks fixes with claude (targeted fixes only, no recompression)
    - retries up to 2 times
    - if still failing after 2 retries, reports the error and leaves the original untouched
4. return the result to the user.

## compression rules

### remove

- articles: a, an, the
- filler: just, really, basically, actually, simply, essentially, generally
- pleasantries: "sure", "certainly", "of course", "happy to", "I'd recommend"
- hedging: "it might be worth", "you could consider", "it would be good to"
- redundant phrasing: "in order to" -> "to", "make sure to" -> "ensure", "the reason is because" -> "because"
- connective fluff: "however", "furthermore", "additionally", "in addition"

### preserve exactly (never modify)

- code blocks (fenced ``` and indented)
- inline code (`backtick content`)
- urls and links (full urls, markdown links)
- file paths (`/src/components/...`, `./config.yaml`)
- commands (`npm install`, `git commit`, `docker build`)
- technical terms (library names, api names, protocols, algorithms)
- proper nouns (project names, people, companies)
- dates, version numbers, numeric values
- env vars (`$HOME`, `NODE_ENV`)

### preserve structure

- all markdown headings (exact heading text; compress the body below)
- bullet hierarchy (keep nesting level)
- numbered lists (keep numbering)
- tables (compress cell text, keep structure)
- frontmatter / yaml headers in markdown files

### compress

- short synonyms: "big" not "extensive", "fix" not "implement a solution for", "use" not "utilize"
- fragments ok: "Run tests before commit" not "You should always run tests before committing"
- drop "you should", "make sure to", "remember to" -- just state the action
- merge redundant bullets that say the same thing differently
- keep one example where several show the same pattern

**critical** anything inside ``` ... ``` is copied exactly. don't remove comments, remove spacing, reorder lines, shorten commands or simplify anything. inline code (`...`) is preserved exactly too -- nothing inside backticks changes.

if the file has code blocks: treat them as read-only regions, compress only the text outside them, and don't merge sections around code.

## pattern

original:
> You should always make sure to run the test suite before pushing any changes to the main branch. This is important because it helps catch bugs early and prevents broken builds from being deployed to production.

compressed:
> Run tests before push to main. Catch bugs early, prevent broken prod deploys.

original:
> The application uses a microservices architecture with the following components. The API gateway handles all incoming requests and routes them to the appropriate service. The authentication service is responsible for managing user sessions and JWT tokens.

compressed:
> Microservices architecture. API gateway route all requests to services. Auth service manage user sessions + JWT tokens.

## boundaries

- only compress natural-language files (.md, .txt, .typ, .typst, .tex, extensionless)
- never modify: .py, .js, .ts, .json, .yaml, .yml, .toml, .env, .lock, .css, .html, .xml, .sql, .sh
- mixed content (prose + code): compress only the prose sections
- unsure whether something is code or prose: leave it unchanged
- the original is backed up as FILE.original.md before overwriting -- in the out-of-tree backup dir (see purpose), not beside the source
- never compress FILE.original.md (skip it)
