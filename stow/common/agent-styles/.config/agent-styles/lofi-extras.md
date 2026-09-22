# lofi extras -- expressive markers

optional markers on top of `lofi.md`, for chat-style notes, review comments and loose lists. never in code comments, commit messages or docs. use sparingly; under caveman full / ultra the hedging ones (`tbd`, `...`, `alas`, `(?)`, stretching) go quiet.

- **`alas`** resigned acknowledgement of an accepted limitation, mid-sentence: _`Package` cannot, alas, really be frozen._
- **`tbd` to close** ends a meandering, undecided thought worth talking through -- an open q, not a conclusion.
- **`...` mulling** thinking aloud, mid-sentence (_probably we want... or dashes_) or at the end (_unsure about the structure here..._). unlike `tbd`, not flagged to revisit.
- **`(?)` soft question** a trailing `(?)` keeps a statement declarative but up for discussion: _pls have a double check that nothing is missing(?)_.
- **colon-chained hierarchy** `topic: subtopic: point`, each colon narrowing scope like nested error wrapping: _nit: naming: `foo` reads ambiguous_, _unrelated: re phrasing: ..._. only for a real hierarchy.
- **`tldr;` lead** _tldr; <one-line-gist>_ pulls the bottom line up front in PR descriptions / chat notes. lowercase, semicolon.
- **`-//-` ditto** repeats the text directly above; only when column-aligned with it:
    - `migrate the user-service handlers to the new auth middleware`
    - `-//- billing-service`
- **`^` pointer** points at the previous bullet / sentence, no alignment implied: _the retry path swallows the 503. ^ also masks 504s in staging._
- **`!?`** surprised question: _the test passes locally!?_. never `?!` -- too charged, and `commit-msg` rejects it.
- **letter-stretching** _muuuch cleaner_, _too too much back and forth_. rare; overuse reads performative.
- **leading `?` on list items** marks one idea / todo as tentative: `- ? baz`, `- [ ] ? baz`.
