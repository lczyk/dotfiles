// TeX-inspired line breaker for funnel's indent + wrap modes.
//
// Splits a single logical input line into visual rows at word boundaries.
// Whitespace between words is "glue" and is swallowed at the chosen break
// point ("foo bar" -> "foo\nbar", the space is dropped). Tokens are never
// split internally except when a single token wider than the available
// width forces a hard cell-split (no hyphenation, no '-' inserted).
//
// Optimisation: dynamic programming over candidate break positions. Each
// line's "badness" = slack^3 where slack = avail - line_cells; the last
// line is free (TeX-style). Total cost = sum of per-line badness. O(N^2)
// edges over word count; cell-walk per edge is O(N), so worst case
// O(N^3). Typical log lines have <50 words.
//
// Returns rows of expanded bytes (tabs in glue replaced with spaces, ctrl
// chars dropped). Callers prepend prefix/indent to each row as needed.

use std::iter::repeat_n;

#[derive(Debug, Clone)]
struct Word {
    bytes: Vec<u8>,
    cells: usize,
}

#[derive(Debug, Clone)]
struct Glue {
    // raw glue bytes (only ' ' or '\t'). Tab width depends on the column
    // where the glue starts, so we compute cells_from / expand_from at
    // line-build time rather than caching.
    bytes: Vec<u8>,
}

impl Glue {
    fn cells_from(&self, start_col: usize) -> usize {
        let mut col = start_col;
        for &b in &self.bytes {
            if b == b'\t' {
                col += 8 - (col % 8);
            } else {
                col += 1;
            }
        }
        col - start_col
    }

    fn expand_from(&self, start_col: usize) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.bytes.len() * 2);
        let mut col = start_col;
        for &b in &self.bytes {
            if b == b'\t' {
                let w = 8 - (col % 8);
                out.extend(repeat_n(b' ', w));
                col += w;
            } else {
                out.push(b' ');
                col += 1;
            }
        }
        out
    }
}

#[derive(Debug)]
struct Tokens {
    words: Vec<Word>,
    // glues[i] = whitespace between words[i] and words[i+1]; len = words-1.
    glues: Vec<Glue>,
}

fn tokenize(content: &[u8]) -> Tokens {
    // leading and trailing whitespace are discarded; per the "swallow on
    // break" rule, whitespace at a line boundary (which includes line start
    // and line end) carries no info. Inter-word whitespace becomes a Glue
    // item whose width is recomputed per emission (for tab handling).
    let s = String::from_utf8_lossy(content);
    let mut words: Vec<Word> = Vec::new();
    let mut glues: Vec<Glue> = Vec::new();
    let mut cur_word: Vec<u8> = Vec::new();
    let mut cur_word_cells: usize = 0;
    let mut cur_glue: Vec<u8> = Vec::new();
    let mut in_glue = false;

    for c in s.chars() {
        if ((c as u32) < 0x20 && c != '\t') || c == '\x7f' {
            continue;
        }
        if c == ' ' || c == '\t' {
            if !cur_word.is_empty() {
                words.push(Word {
                    bytes: std::mem::take(&mut cur_word),
                    cells: cur_word_cells,
                });
                cur_word_cells = 0;
            }
            cur_glue.push(c as u8);
            in_glue = true;
        } else {
            if in_glue {
                let g = std::mem::take(&mut cur_glue);
                // leading glue (no word yet) is dropped.
                if !words.is_empty() {
                    glues.push(Glue { bytes: g });
                }
                in_glue = false;
            }
            let mut buf = [0u8; 4];
            let bs = c.encode_utf8(&mut buf);
            cur_word.extend_from_slice(bs.as_bytes());
            // mono terminal: each codepoint = 1 cell. Wide chars (CJK, emoji)
            // get under-counted; acceptable for v1.
            cur_word_cells += 1;
        }
    }
    if !cur_word.is_empty() {
        words.push(Word {
            bytes: cur_word,
            cells: cur_word_cells,
        });
    }
    Tokens { words, glues }
}

fn split_word(w: &Word, max_cells: usize) -> Vec<Word> {
    let s = String::from_utf8_lossy(&w.bytes).into_owned();
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut idx = 0;
    while idx < chars.len() {
        let end = (idx + max_cells).min(chars.len());
        let chunk: String = chars[idx..end].iter().collect();
        out.push(Word {
            bytes: chunk.into_bytes(),
            cells: end - idx,
        });
        idx = end;
    }
    out
}

// pre-pass: any word wider than max_cells gets hard-split into max_cells-wide
// chunks separated by empty glue. Empty glue has zero cells, so the DP is
// forced to break between fragments (joined line would still overflow) while
// the swallow-on-break rule loses no characters.
fn hard_split(tokens: Tokens, max_cells: usize) -> Tokens {
    let max_cells = max_cells.max(1);
    let Tokens { words, glues } = tokens;
    let mut new_words: Vec<Word> = Vec::new();
    let mut new_glues: Vec<Glue> = Vec::new();
    let last_idx = words.len().saturating_sub(1);
    let mut glues_iter = glues.into_iter();
    for (i, w) in words.into_iter().enumerate() {
        let pieces = if w.cells > max_cells {
            split_word(&w, max_cells)
        } else {
            vec![w]
        };
        let np = pieces.len();
        for (pi, piece) in pieces.into_iter().enumerate() {
            new_words.push(piece);
            if pi + 1 < np {
                new_glues.push(Glue { bytes: Vec::new() });
            }
        }
        if i < last_idx
            && let Some(g) = glues_iter.next()
        {
            new_glues.push(g);
        }
    }
    Tokens {
        words: new_words,
        glues: new_glues,
    }
}

// returns end-column (cells used + start_col) for the line containing
// words[i..=j]; None if the line overflows `width`.
fn line_end_col(
    tokens: &Tokens,
    i: usize,
    j: usize,
    start_col: usize,
    width: usize,
) -> Option<usize> {
    let mut col = start_col;
    col += tokens.words[i].cells;
    if col > width {
        return None;
    }
    for k in (i + 1)..=j {
        col += tokens.glues[k - 1].cells_from(col);
        if col > width {
            return None;
        }
        col += tokens.words[k].cells;
        if col > width {
            return None;
        }
    }
    Some(col)
}

// DP: returns line spans (start_word_inclusive, end_word_inclusive). On
// failure (some word still doesn't fit anywhere -- shouldn't happen after
// hard_split, but defensive) returns one-word-per-line fallback.
fn dp_break(
    tokens: &Tokens,
    width: usize,
    start_col: usize,
    cont_col: usize,
) -> Vec<(usize, usize)> {
    let n = tokens.words.len();
    if n == 0 {
        return Vec::new();
    }
    let mut cost: Vec<u128> = vec![u128::MAX; n];
    let mut prev: Vec<usize> = vec![0; n];
    for j in 0..n {
        for i in 0..=j {
            let line_start = if i == 0 { start_col } else { cont_col };
            let end_col = match line_end_col(tokens, i, j, line_start, width) {
                Some(c) => c,
                None => continue,
            };
            let prev_cost: u128 = if i == 0 {
                0
            } else if cost[i - 1] == u128::MAX {
                continue;
            } else {
                cost[i - 1]
            };
            let avail = width.saturating_sub(line_start);
            let line_cells = end_col - line_start;
            let slack = avail.saturating_sub(line_cells);
            let is_last = j == n - 1;
            let slack_cost: u128 = if is_last { 0 } else { (slack as u128).pow(3) };
            let total = prev_cost.saturating_add(slack_cost);
            if total < cost[j] {
                cost[j] = total;
                prev[j] = i;
            }
        }
    }
    if cost[n - 1] == u128::MAX {
        return (0..n).map(|k| (k, k)).collect();
    }
    let mut lines: Vec<(usize, usize)> = Vec::new();
    let mut j = n - 1;
    loop {
        let i = prev[j];
        lines.push((i, j));
        if i == 0 {
            break;
        }
        j = i - 1;
    }
    lines.reverse();
    lines
}

fn assemble_rows(
    tokens: &Tokens,
    lines: &[(usize, usize)],
    start_col: usize,
    cont_col: usize,
) -> Vec<Vec<u8>> {
    let mut out: Vec<Vec<u8>> = Vec::with_capacity(lines.len());
    for (li, &(i, j)) in lines.iter().enumerate() {
        let line_start = if li == 0 { start_col } else { cont_col };
        let mut row: Vec<u8> = Vec::new();
        let mut col = line_start;
        row.extend_from_slice(&tokens.words[i].bytes);
        col += tokens.words[i].cells;
        for k in (i + 1)..=j {
            let g = tokens.glues[k - 1].expand_from(col);
            col += g.len();
            row.extend_from_slice(&g);
            row.extend_from_slice(&tokens.words[k].bytes);
            col += tokens.words[k].cells;
        }
        out.push(row);
    }
    out
}

// Main entry: word-wrap `content` into visual rows. Each row's bytes are
// returned without prefix/indent (caller prepends those). At least one row
// is returned (possibly empty for empty / whitespace-only content).
//
// `start_col` is the column where the first row begins (after the caller's
// prefix). `cont_col` is the column where every subsequent row begins (used
// for tab expansion in inter-word glue + for slack computation).
pub fn wrap_content(
    content: &[u8],
    width: usize,
    start_col: usize,
    cont_col: usize,
) -> Vec<Vec<u8>> {
    let tokens = tokenize(content);
    if tokens.words.is_empty() {
        // empty or whitespace-only -- emit one empty row so the line still
        // shows up in scrollback.
        return vec![Vec::new()];
    }
    // ensure no word exceeds the narrowest possible line width. Use the
    // smaller of first / continuation availability so any line can host it.
    let avail_first = width.saturating_sub(start_col).max(1);
    let avail_cont = width.saturating_sub(cont_col).max(1);
    let max_cells = avail_first.min(avail_cont);
    let tokens = hard_split(tokens, max_cells);
    let lines = dp_break(&tokens, width, start_col, cont_col);
    let rows = assemble_rows(&tokens, &lines, start_col, cont_col);
    if rows.is_empty() {
        vec![Vec::new()]
    } else {
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(rows: Vec<Vec<u8>>) -> Vec<String> {
        rows.into_iter()
            .map(|r| String::from_utf8(r).unwrap())
            .collect()
    }

    #[test]
    fn empty_content_one_empty_row() {
        assert_eq!(s(wrap_content(b"", 20, 0, 0)), vec![""]);
    }

    #[test]
    fn whitespace_only_one_empty_row() {
        assert_eq!(s(wrap_content(b"   \t  ", 20, 0, 0)), vec![""]);
    }

    #[test]
    fn fits_in_one_row() {
        assert_eq!(
            s(wrap_content(b"hello world", 20, 0, 0)),
            vec!["hello world"]
        );
    }

    #[test]
    fn breaks_at_word_boundary() {
        // width 10, start_col 0: "hello world" = 11 cells, must wrap.
        // options: "hello" / "world" (slack 5 then last=free) or "hello w" /
        // "orld" -- the latter requires hard-split, not chosen because the
        // word boundary fits.
        assert_eq!(
            s(wrap_content(b"hello world", 10, 0, 0)),
            vec!["hello", "world"]
        );
    }

    #[test]
    fn space_swallowed_at_break() {
        // "foo bar" width 4: "foo" then "bar"; the space between is dropped,
        // no trailing space on row 0, no leading space on row 1.
        let rows = s(wrap_content(b"foo bar", 4, 0, 0));
        assert_eq!(rows, vec!["foo", "bar"]);
        assert!(!rows[0].ends_with(' '));
        assert!(!rows[1].starts_with(' '));
    }

    #[test]
    fn no_hyphen_inserted() {
        // long sentence -- never any `-` introduced (none in source).
        let content = b"the quick brown fox jumps over the lazy dog";
        let rows = s(wrap_content(content, 12, 0, 0));
        for r in &rows {
            assert!(!r.contains('-'), "row contained a hyphen: {r:?}");
        }
    }

    #[test]
    fn long_token_hard_split() {
        // single token wider than width: hard cell-split into width-cell chunks.
        let rows = s(wrap_content(b"abcdefghijklmno", 5, 0, 0));
        assert_eq!(rows, vec!["abcde", "fghij", "klmno"]);
    }

    #[test]
    fn balanced_over_greedy() {
        // greedy would emit "aaa bbb" / "c". badness picks the balanced
        // "aaa" / "bbb c" because (slack 1)^3 + 0 < (slack 0)^3 + 0 ... wait.
        // greedy: "aaa bbb"(7,slack=1) + "c"(slack=last=0): cost = 1 + 0 = 1.
        // alt: "aaa"(slack=5) + "bbb c"(slack=2,last=0): cost = 125 + 0 = 125.
        // greedy wins here -- badness is *not* always more-balanced than
        // greedy on contrived inputs. Test asserts greedy-equivalent is picked
        // when it minimises slack^3.
        let rows = s(wrap_content(b"aaa bbb c", 8, 0, 0));
        assert_eq!(rows, vec!["aaa bbb", "c"]);
    }

    #[test]
    fn balanced_when_greedy_overflows() {
        // contrived: greedy first-fit produces unbalanced result; badness
        // prefers tighter packing.
        // "aa bb ccccc" width=7:
        //   greedy: "aa bb"(5,slack 2) + "ccccc"(last,free) -> 8.
        //   alt: "aa"(slack 5) + "bb ccccc"=8 cells -- overflows! invalid.
        //   alt: "aa bb"(slack 2) + "ccccc" (already greedy). only choice.
        let rows = s(wrap_content(b"aa bb ccccc", 7, 0, 0));
        assert_eq!(rows, vec!["aa bb", "ccccc"]);
    }

    #[test]
    fn leading_whitespace_dropped() {
        // leading glue is at a "line boundary" -- per swallow-on-break rule,
        // it gets discarded. Indented log lines lose their indent in
        // indent/wrap mode (use trim mode if indent must be preserved).
        let rows = s(wrap_content(b"  hello world", 20, 0, 0));
        assert_eq!(rows, vec!["hello world"]);
    }

    #[test]
    fn tab_in_glue_expanded() {
        // tab expands relative to col. "a\tb" at start_col 0: col after 'a' =
        // 1, tab -> next 8-stop = col 8 (7 spaces), then 'b' -> col 9.
        let rows = s(wrap_content(b"a\tb", 20, 0, 0));
        assert_eq!(rows, vec!["a       b"]);
    }

    #[test]
    fn cont_col_offset_used() {
        // wrap mode: first line starts at 5 (prefix width), continuation at 0.
        // content "aa bb cc" width=8:
        //   first line avail = 8-5 = 3. fits "aa" (slack 1).
        //   cont line avail = 8. "bb cc" = 5 cells, slack 3, last-free=0.
        //   total = 1^3 + 0 = 1.
        let rows = s(wrap_content(b"aa bb cc", 8, 5, 0));
        assert_eq!(rows, vec!["aa", "bb cc"]);
    }

    #[test]
    fn indent_mode_same_cont_col() {
        // indent mode: first + cont both start at 5. content "aa bb cc"
        // width=8, avail=3 throughout: "aa"/"bb"/"cc".
        let rows = s(wrap_content(b"aa bb cc", 8, 5, 5));
        assert_eq!(rows, vec!["aa", "bb", "cc"]);
    }

    #[test]
    fn regression_tab_off_by_one() {
        // mirrors the screenshot bug: go-test output uses a tab between
        // `:N:` and the body. Ensure every emitted row + prefix col fits in
        // width without any autowrap-induced extra rows.
        let content = b"evaluator/builtin_string_methods.go:15:\t\"match\", \"scan\", \"sub\",";
        let width = 64;
        let start_col = 7; // simulate `[sub2] ` prefix
        let rows = s(wrap_content(content, width, start_col, start_col));
        for (i, r) in rows.iter().enumerate() {
            // every row's content fits within available cells; tabs already
            // expanded to spaces so char count == cell count.
            assert!(
                start_col + r.chars().count() <= width,
                "row {i} overflows: start={start_col}, len={}, row={r:?}",
                r.chars().count()
            );
        }
    }
}
