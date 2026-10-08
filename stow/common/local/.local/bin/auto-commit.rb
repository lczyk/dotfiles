#!/usr/bin/env ruby
# frozen_string_literal: true

# auto-commit -- write a conventional-commit message for the staged changes
# with a cheap claude model, show it, and commit on y.
#
# sends the staged diff (trimmed to a fair share per file when it's big) to
# `claude --print`, sandboxed down to a pure json producer, and gets back a tag
# and a message. -a previews `git add -A` against a copy of the index, so
# nothing is staged unless you confirm.
#
# shells out to the user's `git` and `claude`. the decisions are pure
# functions; everything with side effects (git, claude, the terminal) comes in
# through an Env, which `auto-commit.rb --test` swaps for fakes to run the
# built-in self-test.

require "optparse"
require "json"
require "open3"
require "tmpdir"
require "tempfile"
require "fileutils"

# clean ctrl+c: don't dump the watchdog or open3 reader-thread backtraces.
Thread.report_on_exception = false

VERSION = "0.3.0"

DEFAULT_MODEL = "claude-haiku-5-5"
# haiku 5.5 thinks whatever alwaysThinkingEnabled says; low effort is the knob
# that actually shortens a run.
DEFAULT_VARIANT = "low"

# budget for the diff sent to the model, truncation markers included.
MAX_DIFF_CHARS = 50_000

# kill the cli if a single invocation runs longer than this.
CLAUDE_TIMEOUT = 120

# --- command line -----------------------------------------------------------

class UsageError < StandardError; end

def default_cfg
  { model: DEFAULT_MODEL, variant: DEFAULT_VARIANT, print: false, yes: false, all: false, verbose: 0 }
end

def option_parser(cfg)
  OptionParser.new do |o|
    o.banner = <<~USAGE
      usage: auto-commit.rb [options]

      write a conventional-commit message for the staged changes with a cheap
      claude model, show it, and commit on y. -a previews `git add -A` against
      a copy of the index, so nothing is staged until you confirm.

      options:
    USAGE

    o.on("-p", "--print", "print the message instead of committing") { cfg[:print] = true }
    o.on("-y", "--yes", "commit without the y/n confirmation") { cfg[:yes] = true }
    o.on("-a", "--all", "stage everything (git add -A) before generating") { cfg[:all] = true }
    o.on("-v", "--verbose", "repeatable, all to stderr. -v: progress, -vv: + model output, -vvv: + what we sent") { cfg[:verbose] += 1 }
    o.on("--model MODEL", "model id (default #{cfg[:model]})") { |v| cfg[:model] = v }
    o.on("--variant VARIANT", "passed to claude as --effort (default #{cfg[:variant]}); none pins thinking off instead") { |v| cfg[:variant] = v }
    o.on("--version", "show the version") do
      puts "auto-commit #{VERSION}"
      exit 0
    end
    o.on("-h", "--help", "show this help") do
      puts o
      exit 0
    end
  end
end

# returns cfg; raises UsageError on a bad command line. --help and --version
# print and exit straight away.
def parse_args(argv)
  cfg = default_cfg
  argv = argv.dup
  begin
    option_parser(cfg).parse!(argv)
  rescue OptionParser::ParseError => e
    raise UsageError, "auto-commit: #{e.message} (see --help)"
  end
  raise UsageError, "auto-commit: -p and -y don't mix (see --help)" if cfg[:print] && cfg[:yes]
  raise UsageError, "auto-commit: unexpected argument #{argv.first.inspect} (see --help)" unless argv.empty?

  cfg
end

# --- output -----------------------------------------------------------------

# basic 8-color SGR only (30-37), same palette as gh-retry.
def sgr(code, str)
  "\e[#{code}m#{str}\e[0m"
end

# everything but the message and the y/n prompt goes through here, to stderr.
# warn and bad always show; info and good from -v, debug from -vv, trace from
# -vvv. `live` is the in-place status line, only drawn when stderr is a tty
# and nothing else is logging over it.
class Log
  def initialize(io:, label: nil, color: false, level: 0, live: false)
    @io = io
    @label = label
    @color = color
    @level = level
    @live = live
  end

  def with_label(label)
    Log.new(io: @io, label: label, color: @color, level: @level, live: @live)
  end

  def verbose?
    @level >= 1
  end

  def debugging?
    @level >= 2
  end

  def live?
    @live
  end

  def bad(msg)   line("31", msg) end # red
  def warn(msg)  line("33", msg) end # yellow
  def info(msg)  line("34", msg) if verbose? end # blue
  def good(msg)  line("32", msg) if verbose? end # green
  def debug(msg) line("36", msg) if debugging? end # cyan
  def trace(msg) line("35", msg) if @level >= 3 end # magenta

  # \r + clear-to-eol, then redraw. no newline: the next redraw overwrites it.
  def redraw(msg)
    clear("#{paint("34", tag)}#{msg}")
  end

  def clear(rest = "")
    @io.write("\r\e[2K#{rest}")
    @io.flush
  end

  def paint(code, str)
    @color ? sgr(code, str) : str
  end

  private

  def tag
    @label ? "[auto-commit #{@label}] " : "[auto-commit] "
  end

  def line(code, msg)
    @io.write("#{paint(code, tag)}#{msg}\n")
  end
end

# --- side effects -----------------------------------------------------------

class GitError < StandardError; end
class GenerateError < StandardError; end
class GenerateCancelled < GenerateError; end

# subprocess output is bytes in whatever the locale says; everything here
# measures and slices characters, so pin it to utf-8 and replace the junk.
def utf8(str)
  str.dup.force_encoding(Encoding::UTF_8).scrub
end

# the user's git, run from `cwd` (default: the current directory). `index`
# points every call at another index file (see #preview).
class Git
  def initialize(cwd: nil, index: nil)
    @cwd = cwd
    @index = index
  end

  # outside a repo the diff calls fall back to --no-index and fail with a page
  # of usage, so ask first.
  def check_repo
    run("rev-parse", "--git-dir")
    nil
  end

  # the same paths, in the same order, as --name-only would list.
  def staged_files
    staged_name_status.keys
  end

  def staged_binary_files
    parse_numstat(nul_fields("diff", "--cached", "--numstat"))
  end

  def staged_name_status
    parse_name_status(nul_fields("diff", "--cached", "--name-status"))
  end

  # the whole staged diff, no pathspec: a rename's old path would fall outside
  # one and show the new file as a fresh add, and a non-utf8 name only
  # survives here as its scrubbed copy, which matches nothing. binary files
  # cost one "Binary files ... differ" line. run from the root so a
  # diff.relative config can't narrow it to the cwd.
  def staged_diff
    root = run("rev-parse", "--show-toplevel").strip
    run("diff", "--cached", "--no-ext-diff", chdir: root)
  end

  # any unstaged edit or untracked file. only ask when nothing is staged --
  # `git status` counts staged entries too.
  def worktree_dirty?
    !run("status", "--porcelain", "-z").empty?
  end

  def add_all
    run("add", "-A")
  end

  # -m, not -F: the hooks see exactly what a hand-typed `git commit -m` would.
  def commit(message)
    run("commit", "-m", message)
  end

  # yields a Git that reads and writes a throwaway copy of the index, so
  # add_all can be previewed without touching the repo. a fresh repo has no
  # index file yet; leaving the copy absent is how git spells "empty index",
  # whereas a zero-length file is a parse error.
  def preview
    real = File.expand_path(run("rev-parse", "--git-path", "index").strip, @cwd || Dir.pwd)
    Dir.mktmpdir("auto-commit-") do |dir|
      copy = File.join(dir, "index")
      FileUtils.cp(real, copy) if File.exist?(real)
      yield Git.new(cwd: @cwd, index: copy)
    end
  end

  private

  # the listings all pass -z: without it git quotes any path with non-ascii or
  # special characters, and the quoted form is useless as a pathspec later.
  def nul_fields(*args)
    run(*args, "-z").split("\0", -1)
  end

  # quotePath=false keeps non-ascii paths readable in the diff headers.
  def run(*args, chdir: @cwd)
    cmd = [@index ? { "GIT_INDEX_FILE" => @index } : {}, "git", "-c", "core.quotePath=false", *args]
    cmd << { chdir: chdir } if chdir
    out, err, status = Open3.capture3(*cmd)
    raise GitError, "git #{args.join(" ")} failed: #{utf8(err).strip}" unless status.success?

    utf8(out)
  rescue Errno::ENOENT
    raise GitError, "git not found on PATH"
  rescue ArgumentError => e
    # an argv item can't carry a NUL; spawn refuses before git ever runs.
    raise GitError, "git #{args.first} failed: #{e.message}"
  end
end

# the user's claude cli. #run yields each stdout line and returns the child's
# stderr; a failed, timed-out or interrupted run raises instead.
class Claude
  def initialize(bin: "claude", timeout: CLAUDE_TIMEOUT)
    @bin = bin
    @timeout = timeout
  end

  def run(args)
    raise GenerateError, "`#{@bin}` cli not found on PATH" unless executable?(@bin)

    # stderr goes to a file rather than a pipe: nothing to drain, so a chatty
    # child can't fill a buffer and deadlock the stdout read loop.
    Tempfile.create("auto-commit-claude-") do |errf|
      out_r, out_w = IO.pipe
      # the prompt is an argv item, so the child needs no stdin -- and letting
      # it inherit ours lets it swallow the y/n answer typed after.
      pid = begin
        Process.spawn([@bin, @bin], *args, in: File::NULL, out: out_w, err: errf)
      rescue SystemCallError => e
        out_r.close
        raise GenerateError, "could not run #{@bin}: #{e.message}"
      ensure
        out_w.close
      end

      timed_out = false
      watchdog = Thread.new do
        sleep @timeout
        timed_out = true
        kill(pid)
      end

      interrupted = false
      drained = false
      status = nil
      begin
        out_r.each_line { |line| yield utf8(line) }
        drained = true
      rescue Interrupt
        interrupted = true
      ensure
        out_r.close
        # anything but a clean eof (ctrl+c, or the caller's block raising)
        # leaves the child running with nobody reading it. after a clean eof
        # the watchdog stays up through the wait, in case it never exits.
        kill(pid) unless drained
        status, again = reap(pid)
        watchdog.kill
        interrupted ||= again
      end

      raise GenerateCancelled, "aborted" if interrupted
      raise GenerateError, "claude cli timed out after #{@timeout}s" if timed_out

      errf.rewind
      stderr = utf8(errf.read).strip
      # a signal death reads as rc=-N so it can't pass for a plain exit code.
      rc = status.exitstatus || -status.termsig
      raise GenerateError, "claude cli failed (rc=#{rc}): #{stderr}" unless status.success?

      stderr
    end
  end

  private

  def executable?(bin)
    return File.file?(bin) && File.executable?(bin) if bin.include?("/")

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      path = File.join(dir, bin)
      File.file?(path) && File.executable?(path)
    end
  end

  def kill(pid)
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  end

  # reap the child. returns [status, interrupted], the latter true when a
  # ctrl+c landed while waiting (which kills it, so the wait still ends).
  def reap(pid)
    interrupted = false
    begin
      _, status = Process.wait2(pid)
    rescue Interrupt
      interrupted = true
      kill(pid)
      retry
    end
    [status, interrupted]
  end
end

Env = Struct.new(:git, :claude, :log, :cfg, :out, :input, keyword_init: true)

# --- decisions --------------------------------------------------------------

# mirrors the HEADERS list in the commit-msg hook, in the same order -- a tag
# this doesn't accept is a commit the hook will bounce. the glosses go into the
# prompt; without them the model gets the bare words and has to guess.
TAG_GLOSS = {
  "feat" => "new capability someone could use",
  "fix" => "corrects behaviour that was wrong",
  "docs" => "documentation or comments only",
  "test" => "tests only",
  "refactor" => "restructures code without changing what it does",
  "chore" => "anything else -- deps, tooling, config, formatting, build files",
  "bench" => "benchmarks only",
  "revert" => "undoes an earlier commit",
  "ci" => "ci config, pipelines, workflows",
  "perf" => "same behaviour, measurably faster or lighter",
  "release" => "version bump or release prep, nothing else",
}.freeze

VALID_TAGS = TAG_GLOSS.keys.freeze

# the model sometimes writes the tag into the message too, which then gets
# prefixed again -> `chore: chore: ...`. matches any run of such prefixes.
TAG_PREFIX = /\A(?:(?:#{VALID_TAGS.join("|")})(?:\([^)]*\))?[!?]?:[ \t]*)+/i.freeze

COMMIT_SCHEMA = {
  "type" => "object",
  "properties" => {
    "tag" => { "type" => "string", "enum" => VALID_TAGS },
    "message" => { "type" => "string" },
  },
  "required" => %w[tag message],
  "additionalProperties" => false,
}.freeze

# general conventional-commit rules -- sensible for anyone.
RULES_COMMON = "tag: exactly one of --\n" +
               TAG_GLOSS.map { |tag, gloss| "  #{tag}: #{gloss}\n" }.join +
               "pick the narrowest one that covers the whole diff; `chore` is the fallback " \
               "when nothing narrower fits, not a tie-breaker. " \
               "message: `<subject>` alone, or `<subject>`, a blank line, then `<body>`. " \
               "subject: imperative, no trailing period, <= 72 chars. a terse reminder of what the " \
               "change is about, not a description -- don't name specific functions/classes/variables, " \
               "and don't pad with framing verbs (add, implement, introduce, support for) the tag " \
               "already implies. " \
               "body: include only when the why isn't obvious from the diff; explain why, not what; " \
               "wrap ~72 chars. " \
               "avoid filler/marketing words (robust, seamless, leverage, crucial) and tacked-on " \
               "'-ing' clauses (ensuring..., highlighting..., reflecting...). no emoji. " \
               "ascii only (write -- not an em-dash, -> not an arrow). no backticks anywhere."

# personal voice/locale -- edit (or empty) to taste; appended to the common rules.
RULES_STYLE = "write lowercase and casual, in british english."

RULES = "#{RULES_COMMON} #{RULES_STYLE}"

SYSTEM_PROMPT = "you are a json producer. respond only with json matching the provided schema."

# the cli is invoked with --tools "", so the only tool it should report is the
# one the schema itself installs. bypassPermissions is only defensible while
# that holds -- anything else in the list can be escalated into.
ALLOWED_TOOLS = ["StructuredOutput"].freeze

STATUS_WORD = { "A" => "added", "M" => "modified", "D" => "deleted",
                "R" => "renamed", "C" => "copied", "T" => "type changed" }.freeze

# under -z a numstat record is `<add>\t<del>\t<path>`, except renames/copies,
# which leave the path empty and follow with old and new as separate fields.
# binary files report `-` for both counts. returns the binary paths.
def parse_numstat(fields)
  out = []
  i = 0
  while i < fields.size && !fields[i].empty?
    parts = fields[i].split("\t", -1)
    break unless parts.size == 3

    added, deleted, path = parts
    if path.empty?
      break if i + 2 >= fields.size

      path = fields[i + 2]
      i += 3
    else
      i += 1
    end
    out << path if added == "-" && deleted == "-"
  end
  out
end

# path -> single-letter change kind (A/M/D/R/C/T). renames/copies carry both
# paths, and the new one keys the entry (matches what --name-only reports).
def parse_name_status(fields)
  out = {}
  i = 0
  while i < fields.size && !fields[i].empty?
    kind = fields[i][0]
    n = "RC".include?(kind) ? 2 : 1
    break if i + n >= fields.size

    out[fields[i + n]] = kind
    i += n + 1
  end
  out
end

# keep the head, cut on a line boundary, say what was dropped. the marker
# comes out of the limit, so the result always fits it; a limit too small for
# even the marker keeps nothing (the file still shows in the prompt's list).
def truncate(text, limit)
  return text if text.length <= limit

  marker = ->(omitted) { "\n... [truncated, #{omitted} chars omitted]\n" }
  room = limit - marker.call(text.length).length
  return "" if room.negative?

  head = text[0, room]
  cut = head.rindex("\n")
  head = head[0, cut] if cut
  head + marker.call(text.length - head.length)
end

# one chunk per file, header included. only a header sits at column 0 with
# `diff --git `; body lines always carry a ' ', '+' or '-' prefix, so this
# can't be fooled by a diff of a diff.
def split_by_file(diff)
  chunks = []
  diff.each_line do |line|
    chunks << +"" if chunks.empty? || line.start_with?("diff --git ")
    chunks.last << line
  end
  chunks
end

# match a chunk back to the path that produced it. the header's last field is
# `<prefix>/<path>` (the new name, for renames), so an exact suffix match on
# `/<path>` survives spaces in filenames and near-identical names.
def chunk_label(chunk, paths)
  first = chunk.split("\n", 2).first.to_s
  paths.find { |p| first.end_with?("/#{p}") } || first
end

# max-min fair share: an equal slice each, and whatever a small file doesn't
# need is handed back to be split among the ones still short.
def fair_shares(sizes, budget)
  out = Array.new(sizes.size, 0)
  remaining = budget
  left = sizes.size
  (0...sizes.size).sort_by { |i| [sizes[i], i] }.each do |i|
    take = [sizes[i], remaining / left].min
    out[i] = take
    remaining -= take
    left -= 1
  end
  out
end

# trim a combined diff to `budget` chars by giving every file a fair share of
# it. breadth over depth -- a commit subject summarises the whole change, so
# every file should be represented even if none is represented fully.
def fit(diff, paths, budget = MAX_DIFF_CHARS, log: nil)
  return diff if diff.length <= budget

  chunks = split_by_file(diff)
  allowances = fair_shares(chunks.map(&:length), budget)
  chunks.zip(allowances).map do |chunk, allowance|
    if log&.debugging? && chunk.length > allowance
      log.debug("trimmed #{chunk_label(chunk, paths)}: #{chunk.length} -> #{allowance} chars")
    end
    truncate(chunk, allowance)
  end.join
end

# `  <path> (<kind>, binary)` -- the change kind keeps the model from reading
# an edit as a fresh add, and binary files have their diff withheld.
def fmt_file(path, binary, status)
  tags = [STATUS_WORD[status[path]], (binary.include?(path) ? "binary" : nil)].compact
  tags.empty? ? "  #{path}" : "  #{path} (#{tags.join(", ")})"
end

def render_prompt(files, diff, binary: [], status: {})
  note = files.any? { |f| binary.include?(f) } ? "\nnote: binary files above have no diff content; only filenames were sent.\n" : ""
  "write a commit message for the staged diff below.\n" \
    "#{RULES}\n\n" \
    "files:\n" \
    "#{files.map { |f| fmt_file(f, binary, status) }.join("\n")}\n" \
    "#{note}\n" \
    "diff:\n```\n#{diff.empty? ? "(no text-file diffs)" : diff}\n```\n"
end

# NOTE: these flags sandbox the model to a pure json producer: --tools "" (no
# tools to run), empty+strict mcp, no slash-commands, no session persistence.
# bypassPermissions is safe *because* --tools "" leaves nothing to escalate
# into -- it's only here to stop interactive permission prompts hanging a
# non-interactive run. re-enabling tools means dropping it.
def claude_args(prompt, model:, variant:)
  # the cli spells this --effort; asking for one and pinning thinking off
  # contradict each other, so thinking is only pinned off without a variant.
  thinking = variant.empty? || variant == "none" ? ["--settings", '{"alwaysThinkingEnabled": false}'] : ["--effort", variant]
  ["--print", "--model", model, *thinking,
   "--system-prompt", SYSTEM_PROMPT,
   "--tools", "",
   "--strict-mcp-config", "--mcp-config", '{"mcpServers": {}}',
   "--disable-slash-commands",
   "--setting-sources", "project",
   "--no-session-persistence",
   "--permission-mode", "bypassPermissions",
   "--output-format", "stream-json", "--include-partial-messages", "--verbose",
   "--json-schema", JSON.generate(COMMIT_SCHEMA),
   prompt]
end

# what a single cli invocation told us about itself, built up a line at a time.
Stream = Struct.new(:phase, :chars, :result, :init, :thinking_tokens, :kind, :buf, keyword_init: true)

def new_stream
  Stream.new(phase: "connecting", chars: 0, result: nil, init: nil, thinking_tokens: 0, kind: "", buf: [])
end

def dig_hash(obj, *keys)
  keys.reduce(obj) { |acc, key| acc.is_a?(Hash) ? acc[key] : nil }
end

# feed one stream-json line in. returns false for a line that isn't json at
# all, true otherwise (the caller redraws its status then). `on_block` gets
# each completed thinking/text block; deltas are only buffered when it's set.
def stream_line(stream, raw, on_block: nil)
  raw = raw.strip
  return false if raw.empty?

  begin
    ev = JSON.parse(raw)
  rescue JSON::ParserError
    return false
  end
  return true unless ev.is_a?(Hash)

  case ev["type"]
  when "system"
    if ev["subtype"] == "init"
      stream.init = ev
    elsif ev["subtype"] == "status" && ev["status"] == "requesting"
      stream.phase = "waiting for first token"
    end
  when "result"
    stream.result = ev
    stream.phase = "done"
  when "stream_event"
    stream_event(stream, ev["event"], on_block) if ev["event"].is_a?(Hash)
  end
  true
end

def stream_event(stream, evt, on_block)
  case evt["type"]
  when "message_start"
    stream.phase = "thinking"
  when "content_block_start"
    block = evt["content_block"]
    case dig_hash(block, "type")
    when "thinking"
      stream.phase = stream.kind = "thinking"
    when "text"
      stream.phase = "responding"
      stream.kind = "text"
    when "tool_use"
      stream.phase = "calling #{block.fetch("name", "tool")}"
      stream.kind = ""
    end
  when "content_block_stop"
    flush_block(stream, on_block)
  when "content_block_delta"
    delta = evt["delta"]
    text = { "thinking_delta" => "thinking", "text_delta" => "text",
             "input_json_delta" => "partial_json" }[dig_hash(delta, "type")]
    piece = text && delta[text]
    return unless piece.is_a?(String)

    stream.chars += piece.length
    # the tool call carries the structured output, which gets logged whole
    # once it's parsed. no point buffering it.
    stream.buf << piece if on_block && text != "partial_json"
  when "message_delta"
    # only lives here -- the result event reports it as null.
    n = dig_hash(evt, "usage", "output_tokens_details", "thinking_tokens")
    stream.thinking_tokens += n if n.is_a?(Integer)
  end
end

def flush_block(stream, on_block)
  on_block.call(stream.kind, stream.buf.join) if on_block && !stream.buf.empty?
  stream.buf.clear
end

# the init event is the cli reporting the sandbox it actually built. a tool we
# didn't ask for means --tools "" stopped working, which is what makes
# bypassPermissions safe.
def sandbox_violations(init)
  (Array(init["tools"]) - ALLOWED_TOOLS).uniq.sort
end

# the checks on a finished stream, in order. returns the structured output.
def check_stream(stream)
  # no init event, no way to tell what the model could reach: refuse.
  raise GenerateError, "no init event from claude cli; can't confirm the sandbox" if stream.init.nil?

  extra = sandbox_violations(stream.init)
  unless extra.empty?
    raise GenerateError, "claude cli exposed unexpected tools despite --tools '': #{extra.join(", ")}. " \
                         "refusing to continue under --permission-mode bypassPermissions."
  end
  final = stream.result
  raise GenerateError, "no result event from claude cli" if final.nil?
  raise GenerateError, "claude reported error: #{JSON.generate(final["result"])}" if final["is_error"]

  structured = final["structured_output"]
  raise GenerateError, "missing structured_output in response. raw result: #{JSON.generate(final["result"])}" unless structured.is_a?(Hash)

  structured
end

def parse_commit(obj)
  tag = obj["tag"]
  message = obj["message"]
  raise GenerateError, "invalid tag from model: #{JSON.generate(tag)}" unless VALID_TAGS.include?(tag)

  message = message.strip.sub(TAG_PREFIX, "").strip if message.is_a?(String)
  raise GenerateError, "empty message from model" unless message.is_a?(String) && !message.empty?

  [tag, message]
end

# stitch the tag onto the first line of the body.
def format_message(tag, body)
  first, rest = body.split("\n", 2)
  rest.to_s.strip.empty? ? "#{tag}: #{first}" : "#{tag}: #{first}\n#{rest}"
end

# the y/n answer as text, nil at eof.
def read_reply(io)
  line = io.gets
  line && utf8(line)
end

def accepts?(reply)
  ["", "y", "yes"].include?(reply.strip.downcase)
end

def usage_summary(final, elapsed)
  usage = final["usage"].is_a?(Hash) ? final["usage"] : {}
  fresh, cache_w, cache_r, out_tok = %w[input_tokens cache_creation_input_tokens
                                        cache_read_input_tokens output_tokens].map { |k| usage[k].to_i }
  parts = ["#{fresh} fresh"]
  parts << "#{cache_w} cache write" if cache_w.positive?
  parts << "#{cache_r} cache read" if cache_r.positive?
  format("done in %<s>.1fs (%<in>d in [%<parts>s], %<out>d out)",
         s: elapsed, in: fresh + cache_w + cache_r, parts: parts.join(", "), out: out_tok)
end

def run_details(final, thinking_tokens)
  used = final["modelUsage"].is_a?(Hash) ? final["modelUsage"].keys : []
  bits = ["stop=#{final["stop_reason"] || "?"}", "resolved=#{used.empty? ? "?" : used.join(", ")}"]
  bits << format("cost=$%.5f", final["total_cost_usd"]) if final["total_cost_usd"].is_a?(Numeric)
  bits << "thinking=#{thinking_tokens} tok" if thinking_tokens.positive?
  { "ttft_ms" => "ttft", "duration_api_ms" => "api" }.each do |key, label|
    bits << "#{label}=#{final[key]}ms" unless final[key].nil?
  end
  bits.join(" ")
end

# --- claude -----------------------------------------------------------------

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

# one sandboxed model call. returns the structured output, unvalidated.
def ask_claude(env, prompt)
  cfg = env.cfg
  log = env.log.with_label("claude")
  log.debug "running: claude --model #{cfg[:model]} --effort #{cfg[:variant]} ..."
  log.trace "prompt (#{prompt.length} chars):\n#{prompt}"

  started = monotonic
  stream = new_stream
  last = nil
  # the in-place status line would trample the phase logs, so under -v the
  # phases are logged instead, one line each.
  on_phase = lambda do |phase, chars|
    if log.live?
      log.redraw("#{phase} (#{format("%.0f", monotonic - started)}s#{chars.positive? ? ", #{chars} chars" : ""})")
    elsif phase != last
      log.info phase
      last = phase
    end
  end
  # thinking display defaults to omitted on current models, so most thinking
  # blocks arrive empty.
  on_block = log.debugging? ? ->(kind, text) { log.debug "#{kind}:\n#{text.strip}" unless text.strip.empty? } : nil

  log.redraw("connecting (0s)") if log.live?
  begin
    stderr = env.claude.run(claude_args(prompt, model: cfg[:model], variant: cfg[:variant])) do |line|
      on_phase.call(stream.phase, stream.chars) if stream_line(stream, line, on_block: on_block)
    end
  ensure
    log.clear if log.live?
  end
  flush_block(stream, on_block)
  log.trace "stderr:\n#{stderr}" unless stderr.empty?

  init = stream.init
  if init
    log.trace "sandbox: model=#{init["model"]} tools=#{Array(init["tools"]).join(",")} " \
              "mcp=#{JSON.generate(init["mcp_servers"])} permissions=#{init["permissionMode"]}"
  end
  structured = check_stream(stream)
  final = stream.result
  log.info usage_summary(final, monotonic - started)
  # visible without -v: it's the likeliest cause of whatever fails next.
  log.warn "output hit the token cap; the message may be truncated" if final["stop_reason"] == "max_tokens"
  log.debug run_details(final, stream.thinking_tokens)
  log.debug "structured_output: #{JSON.generate(structured)}"
  structured
end

# returns [tag, message] for the staged `files` and their combined `full` diff.
def generate_message(env, files, full, binary: [], status: {})
  raise GenerateError, "no staged files" if files.empty?

  diff = fit(full, files, MAX_DIFF_CHARS, log: env.log)
  if diff.length < full.length
    env.log.info "#{files.size} files, diff #{full.length} chars > #{MAX_DIFF_CHARS} -> trimmed to #{diff.length}"
  else
    env.log.info "#{files.size} files, diff #{full.length} chars, sent whole"
  end

  parse_commit(ask_claude(env, render_prompt(files, diff, binary: binary, status: status)))
end

# --- commit flow ------------------------------------------------------------

class NothingToCommit < StandardError; end

# stage (if asked), read the index, and return the commit message. `git` is
# the preview copy under -a.
def compose(env, git = env.git)
  git.add_all if env.cfg[:all]
  status = git.staged_name_status
  files = status.keys
  binary = git.staged_binary_files
  if files.empty?
    if !env.cfg[:all] && git.worktree_dirty?
      raise NothingToCommit, "nothing staged. `git add` what you want committed, or pass -a to stage everything."
    end

    raise NothingToCommit, "working tree clean; nothing to commit."
  end

  unless binary.empty?
    env.log.warn "#{binary.size} binary file(s) staged; only filenames will be sent: #{binary.sort.join(", ")}"
  end
  # binary files go by name alone (git's diff carries no content for them),
  # so with nothing else staged the diff isn't fetched.
  full = (files - binary).empty? ? "" : git.staged_diff
  format_message(*generate_message(env, files, full, binary: binary, status: status))
end

# ctrl+c, or eof at the question: finish the line and say so.
def aborted(env)
  env.out.write("\n")
  env.log.warn "aborted."
  130
end

# the whole run. returns the exit code; never exits itself.
def run(env)
  cfg = env.cfg
  log = env.log
  log.info "resolved: all=#{cfg[:all]} yes=#{cfg[:yes]} print=#{cfg[:print]} model=#{cfg[:model]} variant=#{cfg[:variant]}"

  env.git.check_repo
  # -a is previewed against a copy of the index; the real staging only happens
  # once the message is confirmed.
  message = cfg[:all] ? env.git.preview { |git| compose(env, git) } : compose(env)

  env.out.puts message
  return 0 if cfg[:print]

  env.out.puts
  unless cfg[:yes]
    reply = env.input.call("#{log.paint("34", "commit with this message? [Y/n]")} ")
    return aborted(env) if reply.nil?
    unless accepts?(reply)
      log.warn "aborted."
      return 1
    end
  end

  env.git.add_all if cfg[:all]
  env.git.commit(message)
  log.good "committed."
  0
rescue GitError => e
  log.bad e.message
  2
rescue GenerateCancelled, Interrupt
  aborted(env)
rescue NothingToCommit, GenerateError => e
  log.bad e.message
  1
end

# --- main -------------------------------------------------------------------

def main(argv)
  cfg = begin
    parse_args(argv)
  rescue UsageError => e
    warn e.message
    exit 2
  end

  # one colour decision for both streams: `auto-commit.rb | cat` should come
  # out plain even though the logs on stderr still face a tty.
  color = $stdout.tty? && $stderr.tty? && !ENV.key?("NO_COLOR")
  log = Log.new(io: $stderr, color: color, level: cfg[:verbose], live: $stderr.tty? && cfg[:verbose].zero?)
  input = lambda do |prompt|
    $stdout.write(prompt)
    $stdout.flush
    read_reply($stdin)
  end
  env = Env.new(git: Git.new, claude: Claude.new, log: log, cfg: cfg, out: $stdout, input: input)
  exit run(env)
end

# --- self-test (auto-commit.rb --test) --------------------------------------

if ARGV.first == "--test"
  require "minitest"
  require "stringio"

  TESTS = []

  def test(name, &blk)
    TESTS << [name, blk]
  end

  class SelfTest
    include Minitest::Assertions
    attr_accessor :assertions

    def initialize
      @assertions = 0
    end
  end

  # an in-memory index. add_all stages the unstaged paths; preview hands out a
  # copy, so whatever happens inside leaves this one alone. calls are recorded
  # (the preview copy shares the log, tagged :preview), and an Exception in
  # `errors` is raised by the method it's keyed on.
  class FakeGit
    attr_reader :calls

    def initialize(staged: [], unstaged: [], binary: [], status: {}, diff: "", errors: {}, calls: [], tag: :real)
      @staged = staged.dup
      @unstaged = unstaged.dup
      @binary = binary
      @status = status
      @diff = diff
      @errors = errors
      @calls = calls
      @tag = tag
    end

    def check_repo
      call(:check_repo)
      nil
    end

    def staged_files
      call(:staged_files)
      @staged.dup
    end

    def staged_binary_files
      call(:staged_binary_files)
      @binary & @staged
    end

    def staged_name_status
      call(:staged_name_status)
      @staged.map { |path| [path, @status.fetch(path, "M")] }.to_h
    end

    def staged_diff
      call(:staged_diff)
      @diff
    end

    def worktree_dirty?
      call(:worktree_dirty?)
      !@unstaged.empty?
    end

    def add_all
      call(:add_all)
      @staged |= @unstaged
      @unstaged = []
    end

    def commit(message)
      call(:commit, message)
    end

    def preview
      call(:preview)
      yield FakeGit.new(staged: @staged, unstaged: @unstaged, binary: @binary, status: @status,
                        diff: @diff, errors: @errors, calls: @calls, tag: :preview)
    end

    private

    def call(name, *args)
      @calls << [@tag, name, *args]
      raise @errors[name] if @errors.key?(name)
    end
  end

  # replays canned stream-json lines, then raises `raise_after` if set.
  class FakeClaude
    attr_reader :calls

    def initialize(lines = [], stderr: "", raise_after: nil)
      @lines = lines
      @stderr = stderr
      @raise_after = raise_after
      @calls = []
    end

    def run(args)
      @calls << args
      @lines.each { |line| yield line }
      raise @raise_after if @raise_after

      @stderr
    end
  end

  def ev(obj)
    JSON.generate(obj)
  end

  def sev(event)
    ev("type" => "stream_event", "event" => event)
  end

  def delta(type, key, text)
    sev("type" => "content_block_delta", "delta" => { "type" => type, key => text })
  end

  def block_start(type, extra = {})
    sev("type" => "content_block_start", "content_block" => { "type" => type }.merge(extra))
  end

  def stream_event_line(type)
    sev("type" => type)
  end

  # canned lines in, finished Stream out -- the state machine without a child.
  def parse_stream(lines, on_phase: nil, on_block: nil)
    stream = new_stream
    lines.each do |line|
      on_phase&.call(stream.phase, stream.chars) if stream_line(stream, line, on_block: on_block)
    end
    flush_block(stream, on_block)
    stream
  end

  INIT_OK = { "type" => "system", "subtype" => "init", "tools" => ["StructuredOutput"], "model" => "m" }.freeze

  # a clean run that answers with `structured`.
  def answer(structured, result: {})
    [ev(INIT_OK), stream_event_line("message_start"),
     ev({ "type" => "result", "structured_output" => structured,
          "usage" => { "input_tokens" => 10, "cache_read_input_tokens" => 5, "output_tokens" => 7 } }.merge(result))]
  end

  def fake_env(git: FakeGit.new, claude: FakeClaude.new, replies: [], verbose: 0, **cfg)
    out = StringIO.new
    err = StringIO.new
    prompts = []
    input = lambda do |prompt|
      prompts << prompt
      reply = replies.shift
      raise reply if reply.is_a?(Exception) || reply == Interrupt

      reply
    end
    cfg = default_cfg.merge(verbose: verbose).merge(cfg)
    env = Env.new(git: git, claude: claude, log: Log.new(io: err, level: verbose), cfg: cfg, out: out, input: input)
    [env, out, err, prompts]
  end

  def diff_chunk(path, body_lines)
    body = (0...body_lines).map { |i| "+line #{i}\n" }.join
    "diff --git c/#{path} i/#{path}\n--- c/#{path}\n+++ i/#{path}\n@@ -0,0 +1 @@\n#{body}"
  end

  def sh(*args, stdin: "")
    out, status = Open3.capture2e(*args, stdin_data: stdin)
    raise "#{args.join(" ")} failed:\n#{out}" unless status.success?

    out
  end

  def in_tmpdir(&blk)
    Dir.mktmpdir("auto-commit-test-", &blk)
  end

  def assert_quick(seconds = 3)
    started = monotonic
    yield
    assert_operator monotonic - started, :<, seconds
  end

  # a throwaway repo as the cwd, with a local identity so commits work
  # whatever the user's global config says.
  def in_repo
    in_tmpdir do |dir|
      Dir.chdir(dir) do
        sh("git", "init", "-q")
        sh("git", "config", "user.email", "t@t")
        sh("git", "config", "user.name", "t")
        sh("git", "config", "commit.gpgsign", "false")
        yield dir
      end
    end
  end

  def fixture_commit(subject)
    sh("git", "commit", "-qm", subject)
  end

  # a stand-in claude on disk: records its argv, then runs `body`.
  def fake_claude_bin(dir, body)
    path = File.join(dir, "fake-claude")
    File.write(path, "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"#{dir}/argv\"\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  # --- command line ---

  test "parse_args: defaults and flags" do
    assert_equal default_cfg, parse_args([])
    cfg = parse_args(%w[-a -vvv --model m --variant high -y])
    assert_equal [true, 3, "m", "high", true], cfg.values_at(:all, :verbose, :model, :variant, :yes)
    assert_equal true, parse_args(%w[-ap])[:print]
  end

  test "parse_args: usage errors" do
    e = assert_raises(UsageError) { parse_args(%w[-p -y]) }
    assert_equal "auto-commit: -p and -y don't mix (see --help)", e.message
    e = assert_raises(UsageError) { parse_args(%w[--model]) }
    assert_equal "auto-commit: missing argument: --model (see --help)", e.message
    assert_raises(UsageError) { parse_args(%w[--bogus]) }
    e = assert_raises(UsageError) { parse_args(%w[junk]) }
    assert_match(/unexpected argument "junk"/, e.message)
  end

  # --- output ---

  test "log: levels, labels and colour" do
    io = StringIO.new
    Log.new(io: io).info("hidden")
    Log.new(io: io).warn("shown")
    Log.new(io: io, level: 1).with_label("claude").info("hi")
    Log.new(io: io, level: 1).debug("hidden")
    Log.new(io: io, level: 3).trace("deep")
    Log.new(io: io, color: true).bad("no")
    assert_equal "[auto-commit] shown\n[auto-commit claude] hi\n[auto-commit] deep\n\e[31m[auto-commit] \e[0mno\n", io.string
  end

  test "log: live status redraws in place" do
    io = StringIO.new
    log = Log.new(io: io, live: true).with_label("claude")
    assert log.live?
    log.redraw("thinking (1s)")
    log.clear
    assert_equal "\r\e[2K[auto-commit claude] thinking (1s)\r\e[2K", io.string
  end

  # --- decisions ---

  test "parse_numstat: binary files, renames included" do
    fields = ["1\t0\ta.txt", "-\t-\tblob.dat", "-\t-\t", "old.bin", "new.bin", "2\t1\t", "o.txt", "n.txt", ""]
    assert_equal %w[blob.dat new.bin], parse_numstat(fields)
    assert_equal [], parse_numstat([""])
    assert_equal [], parse_numstat(["garbage"])
  end

  test "parse_name_status: new path keys renames" do
    fields = ["M", "a.py", "R100", "old.txt", "new.txt", "A", "blob.dat", ""]
    assert_equal({ "a.py" => "M", "new.txt" => "R", "blob.dat" => "A" }, parse_name_status(fields))
    assert_equal({}, parse_name_status(["R100", "old.txt"]))
  end

  test "truncate: cuts on a line boundary" do
    assert_equal "abc", truncate("abc", 10)
    text = (1..20).map { |i| "line #{i}\n" }.join
    out = truncate(text, 60)
    assert_equal "line 1\nline 2\nline 3\n... [truncated, #{text.length - 20} chars omitted]\n", out
    assert_operator out.length, :<=, 60
    # a limit smaller than the marker keeps nothing at all.
    assert_equal "", truncate("aaaa\nbbbb\ncccc\n", 12)
  end

  test "split_by_file: not fooled by a diff of a diff" do
    inner = diff_chunk("a.txt", 1) + "diff --git c/b.txt i/b.txt\n+++ b\n"
    nested = inner.lines.map { |l| "+#{l}" }.join
    chunks = split_by_file("diff --git c/p.patch i/p.patch\n#{nested}#{diff_chunk("real.txt", 1)}")
    assert_equal 2, chunks.size
    assert chunks[0].start_with?("diff --git c/p.patch")
    assert chunks[1].start_with?("diff --git c/real.txt")
    assert_equal [], split_by_file("")
  end

  test "chunk_label: spaces and shared suffixes" do
    paths = ["a.py", "xa.py", "my file.txt"]
    assert_equal "xa.py", chunk_label("diff --git c/xa.py i/xa.py\nbody", paths)
    assert_equal "a.py", chunk_label("diff --git c/a.py i/a.py\nbody", paths)
    assert_equal "my file.txt", chunk_label("diff --git c/my file.txt i/my file.txt", paths)
    assert_equal "diff --git c/z i/z", chunk_label("diff --git c/z i/z", paths)
  end

  test "fair_shares: max-min fair" do
    assert_equal [370, 10, 10, 10], fair_shares([1000, 10, 10, 10], 400)
    assert_equal [5, 5], fair_shares([5, 5], 100)
    assert_equal [25, 25], fair_shares([100, 100], 50)
    # ties keep their order, so the remainder lands the same way every time.
    assert_equal [33, 33, 34], fair_shares([50, 50, 50], 100)
  end

  test "fit: every file stays represented" do
    diff = diff_chunk("big.py", 400) + diff_chunk("small.py", 2)
    assert_operator diff.length, :>, 1000
    io = StringIO.new
    out = fit(diff, ["big.py", "small.py"], 1000, log: Log.new(io: io, level: 2))
    assert_operator out.length, :<=, 1000
    assert_includes out, "diff --git c/small.py"
    assert_includes out, "diff --git c/big.py"
    assert_includes out, "truncated"
    assert_match(/trimmed big\.py: \d+ -> \d+ chars/, io.string)
    small = diff_chunk("a.py", 2)
    assert_same small, fit(small, ["a.py"], 10_000)
  end

  test "fmt_file: annotations" do
    assert_equal "  a.py (modified)", fmt_file("a.py", [], "a.py" => "M")
    assert_equal "  a.bin (added, binary)", fmt_file("a.bin", ["a.bin"], "a.bin" => "A")
    assert_equal "  a.py", fmt_file("a.py", [], {})
  end

  test "tags: the commit-msg hook's list, in its order" do
    assert_equal %w[feat fix docs test refactor chore bench revert ci perf release], VALID_TAGS
    assert_equal VALID_TAGS, COMMIT_SCHEMA["properties"]["tag"]["enum"]
    VALID_TAGS.each { |tag| assert_includes RULES, "  #{tag}: #{TAG_GLOSS[tag]}\n" }
  end

  test "rules: no literal escapes, no backticks allowed" do
    refute_includes RULES, "\\n"
    assert_includes RULES, "no backticks anywhere"
    assert RULES.end_with?("ascii only (write -- not an em-dash, -> not an arrow). no backticks anywhere. #{RULES_STYLE}")
  end

  test "render_prompt: files, binary note, empty diff" do
    prompt = render_prompt(["a.py", "b.bin"], "", binary: ["b.bin"], status: { "a.py" => "M", "b.bin" => "A" })
    assert prompt.start_with?("write a commit message for the staged diff below.\n#{RULES}\n\nfiles:\n")
    assert_includes prompt, "  a.py (modified)\n  b.bin (added, binary)\n\nnote: binary files above"
    assert prompt.end_with?("only filenames were sent.\n\ndiff:\n```\n(no text-file diffs)\n```\n")
    plain = render_prompt(["a.py"], "D\n")
    assert plain.end_with?("files:\n  a.py\n\ndiff:\n```\nD\n\n```\n")
  end

  test "claude_args: sandbox flags, thinking off by default" do
    args = claude_args("PROMPT", model: "m", variant: "none")
    assert_equal ["--print", "--model", "m", "--settings", '{"alwaysThinkingEnabled": false}',
                  "--system-prompt", SYSTEM_PROMPT, "--tools", "",
                  "--strict-mcp-config", "--mcp-config", '{"mcpServers": {}}',
                  "--disable-slash-commands", "--setting-sources", "project", "--no-session-persistence",
                  "--permission-mode", "bypassPermissions",
                  "--output-format", "stream-json", "--include-partial-messages", "--verbose",
                  "--json-schema"], args[0..-3]
    assert_equal COMMIT_SCHEMA, JSON.parse(args[-2])
    assert_equal "PROMPT", args.last
    assert_equal ["--effort", "high"], claude_args("p", model: "m", variant: "high")[3, 2]
    assert_equal "--settings", claude_args("p", model: "m", variant: "")[3]
  end

  test "parse_stream: result and char count, junk skipped" do
    phases = []
    lines = ["", "not json", "[1]",
             ev("type" => "system", "subtype" => "status", "status" => "requesting"),
             stream_event_line("message_start"),
             delta("text_delta", "text", "hello"),
             delta("thinking_delta", "thinking", "abc"),
             delta("input_json_delta", "partial_json", "{}"),
             ev("type" => "result", "structured_output" => { "tag" => "fix", "message" => "x" })]
    stream = parse_stream(lines, on_phase: ->(phase, _) { phases << phase })
    assert_equal({ "tag" => "fix", "message" => "x" }, stream.result["structured_output"])
    assert_equal 10, stream.chars
    assert_equal ["connecting", "waiting for first token", "thinking", "thinking", "thinking", "thinking", "done"], phases
    assert_nil parse_stream([stream_event_line("message_start")]).result
  end

  test "parse_stream: phase transitions" do
    phases = []
    lines = [stream_event_line("message_start"), block_start("text"),
             block_start("tool_use", "name" => "grep"), ev("type" => "result")]
    parse_stream(lines, on_phase: ->(phase, _) { phases << phase })
    assert_equal ["thinking", "responding", "calling grep", "done"], phases
  end

  test "parse_stream: init kept, thinking tokens summed, not clobbered" do
    thinking = lambda do |n|
      ev("type" => "stream_event",
         "event" => { "type" => "message_delta", "usage" => { "output_tokens_details" => { "thinking_tokens" => n } } })
    end
    lines = [ev(INIT_OK), thinking.call(228), thinking.call(2),
             ev("type" => "result", "usage" => { "output_tokens_details" => nil })]
    stream = parse_stream(lines)
    assert_equal ["StructuredOutput"], stream.init["tools"]
    assert_equal 230, stream.thinking_tokens
  end

  test "parse_stream: completed blocks, last one flushed, tool json not buffered" do
    blocks = []
    lines = [block_start("thinking"), delta("thinking_delta", "thinking", "hmm"), stream_event_line("content_block_stop"),
             block_start("tool_use", "name" => "StructuredOutput"), delta("input_json_delta", "partial_json", "{}"),
             stream_event_line("content_block_stop"),
             block_start("text"), delta("text_delta", "text", "answer")]
    stream = parse_stream(lines, on_block: ->(kind, text) { blocks << [kind, text] })
    assert_equal [%w[thinking hmm], %w[text answer]], blocks
    assert_equal 11, stream.chars
  end

  test "check_stream: no init refused, sandbox next, then result checks in order" do
    good = parse_stream(answer({ "tag" => "fix", "message" => "x" }))
    assert_equal({ "tag" => "fix", "message" => "x" }, check_stream(good))

    leaky = parse_stream([ev(INIT_OK.merge("tools" => %w[StructuredOutput Bash Bash Read]))])
    e = assert_raises(GenerateError) { check_stream(leaky) }
    assert_equal "claude cli exposed unexpected tools despite --tools '': Bash, Read. " \
                 "refusing to continue under --permission-mode bypassPermissions.", e.message
    {
      [] => "no init event from claude cli; can't confirm the sandbox",
      [ev("type" => "result", "structured_output" => { "tag" => "fix" })] => "no init event from claude cli; can't confirm the sandbox",
      [ev(INIT_OK)] => "no result event from claude cli",
      [ev(INIT_OK), ev("type" => "result", "is_error" => true, "result" => "rate limited")] => 'claude reported error: "rate limited"',
      [ev(INIT_OK), ev("type" => "result", "result" => nil)] => "missing structured_output in response. raw result: null",
    }.each do |lines, want|
      e = assert_raises(GenerateError) { check_stream(parse_stream(lines)) }
      assert_equal want, e.message
    end
  end

  test "parse_commit: ok, and repeated tag prefixes stripped" do
    assert_equal %w[feat add\ thing], parse_commit("tag" => "feat", "message" => "  add thing  ")
    {
      "chore: add dependency tree notes" => "add dependency tree notes",
      "chore: chore: add dependency tree notes" => "add dependency tree notes",
      "Chore(deps)!: bump uv" => "bump uv",
      "feat: add thing\n\nwhy it matters" => "add thing\n\nwhy it matters",
      # only a tag followed by a colon counts as a prefix.
      "fixup handling of feat: lines" => "fixup handling of feat: lines",
      "docs: docs site layout" => "docs site layout",
    }.each { |raw, want| assert_equal ["chore", want], parse_commit("tag" => "chore", "message" => raw), raw }
  end

  test "parse_commit: bad tag, empty or prefix-only message" do
    e = assert_raises(GenerateError) { parse_commit("tag" => "nope", "message" => "x") }
    assert_equal 'invalid tag from model: "nope"', e.message
    e = assert_raises(GenerateError) { parse_commit("message" => "x") }
    assert_equal "invalid tag from model: null", e.message
    ["", "   ", nil, "chore: ", 3].each do |msg|
      e = assert_raises(GenerateError) { parse_commit("tag" => "fix", "message" => msg) }
      assert_equal "empty message from model", e.message
    end
  end

  test "format_message and accepts?" do
    assert_equal "fix: patch bug", format_message("fix", "patch bug")
    assert_equal "fix: patch bug", format_message("fix", "patch bug\n  \n")
    assert_equal "fix: patch bug\n\nbecause", format_message("fix", "patch bug\n\nbecause")
    ["", "y", "Y", " yes\n"].each { |r| assert accepts?(r), r.inspect }
    ["n", "no", "yy", "q"].each { |r| refute accepts?(r), r.inspect }
  end

  test "usage_summary and run_details" do
    final = { "usage" => { "input_tokens" => 10, "cache_creation_input_tokens" => 0, "cache_read_input_tokens" => 5, "output_tokens" => 7 },
              "stop_reason" => "end_turn", "modelUsage" => { "claude-haiku-4-5" => {} },
              "total_cost_usd" => 0.0012, "ttft_ms" => 300, "duration_api_ms" => 900 }
    assert_equal "done in 1.2s (15 in [10 fresh, 5 cache read], 7 out)", usage_summary(final, 1.24)
    assert_equal "stop=end_turn resolved=claude-haiku-4-5 cost=$0.00120 thinking=3 tok ttft=300ms api=900ms",
                 run_details(final, 3)
    assert_equal "done in 0.0s (0 in [0 fresh], 0 out)", usage_summary({ "usage" => nil }, 0)
    assert_equal "stop=? resolved=?", run_details({}, 0)
  end

  # --- generate, with fakes ---

  test "generate_message: no files" do
    env, = fake_env
    e = assert_raises(GenerateError) { generate_message(env, [], "") }
    assert_equal "no staged files", e.message
  end

  test "generate_message: one call, diff and statuses in the prompt" do
    claude = FakeClaude.new(answer({ "tag" => "fix", "message" => "patch bug" }))
    env, = fake_env(claude: claude)
    assert_equal %w[fix patch\ bug], generate_message(env, ["a.py"], "diff-a", status: { "a.py" => "M" })
    assert_equal 1, claude.calls.size
    prompt = claude.calls[0].last
    assert_includes prompt, "diff-a"
    assert_includes prompt, "  a.py (modified)"
  end

  test "compose: no diff fetched when only binaries are staged" do
    [[%w[a.py b.bin], true], [%w[b.bin], false]].each do |staged, fetched|
      git = FakeGit.new(staged: staged, binary: ["b.bin"], diff: "d")
      env, = fake_env(git: git, claude: FakeClaude.new(answer({ "tag" => "chore", "message" => "x" })))
      compose(env)
      assert_equal fetched, git.calls.include?([:real, :staged_diff]), staged.inspect
    end
  end

  test "generate_message: a huge diff stays one call and keeps every file" do
    diff = diff_chunk("big.py", MAX_DIFF_CHARS / 8) + diff_chunk("small.py", 1)
    assert_operator diff.length, :>, MAX_DIFF_CHARS
    claude = FakeClaude.new(answer({ "tag" => "refactor", "message" => "split module" }))
    env, _, err = fake_env(claude: claude, verbose: 1)
    assert_equal %w[refactor split\ module], generate_message(env, ["big.py", "small.py"], diff)
    assert_equal 1, claude.calls.size
    prompt = claude.calls[0].last
    assert_includes prompt, "diff --git c/big.py"
    assert_includes prompt, "diff --git c/small.py"
    assert_includes prompt, "truncated"
    assert_match(/2 files, diff #{diff.length} chars > #{MAX_DIFF_CHARS} -> trimmed to \d+/, err.string)
  end

  test "ask_claude: phases and summary under -v, details under -vv" do
    lines = [stream_event_line("message_start"), block_start("thinking"), delta("thinking_delta", "thinking", "hmm"),
             stream_event_line("content_block_stop"),
             block_start("thinking"), delta("thinking_delta", "thinking", ""), stream_event_line("content_block_stop")] +
            answer({ "tag" => "fix", "message" => "x" })
    env, _, err = fake_env(claude: FakeClaude.new(lines), verbose: 2)
    ask_claude(env, "p")
    assert_equal 1, err.string.scan(/thinking:\n/).size
    log = err.string
    assert_equal 1, log.scan(/^\[auto-commit claude\] thinking$/).size
    assert_match(/^\[auto-commit claude\] done in \d+\.\ds \(15 in \[10 fresh, 5 cache read\], 7 out\)$/, log)
    assert_match(/^\[auto-commit claude\] thinking:\nhmm$/, log)
    assert_match(/^\[auto-commit claude\] structured_output: \{"tag":"fix","message":"x"\}$/, log)
    refute_match(/prompt \(/, log)
  end

  test "ask_claude: token cap warns without -v, stderr shows at -vvv" do
    claude = FakeClaude.new(answer({ "tag" => "fix", "message" => "x" }, result: { "stop_reason" => "max_tokens" }), stderr: "noise")
    env, _, err = fake_env(claude: claude)
    ask_claude(env, "p")
    assert_equal "[auto-commit claude] output hit the token cap; the message may be truncated\n", err.string
    env, _, err = fake_env(claude: FakeClaude.new(answer({ "tag" => "fix", "message" => "x" }), stderr: "noise"), verbose: 3)
    ask_claude(env, "PROMPT")
    assert_match(/^\[auto-commit claude\] prompt \(6 chars\):\nPROMPT$/, err.string)
    assert_match(/^\[auto-commit claude\] stderr:\nnoise$/, err.string)
    assert_match(/^\[auto-commit claude\] sandbox: model=m tools=StructuredOutput mcp=null permissions=$/, err.string)
  end

  # --- run, with fakes ---

  OK = { "tag" => "feat", "message" => "add thing\n\nbecause" }.freeze

  test "run: commits on an empty reply" do
    git = FakeGit.new(staged: ["a.py"], status: { "a.py" => "M" }, diff: "d")
    env, out, err, prompts = fake_env(git: git, claude: FakeClaude.new(answer(OK)), replies: ["\n"])
    assert_equal 0, run(env)
    assert_equal "feat: add thing\n\nbecause\n\n", out.string
    assert_equal ["commit with this message? [Y/n] "], prompts
    assert_includes git.calls, [:real, :commit, "feat: add thing\n\nbecause"]
    assert_equal "", err.string
  end

  test "run: -p prints only, -y skips the question" do
    git = FakeGit.new(staged: ["a.py"])
    env, out, _, prompts = fake_env(git: git, claude: FakeClaude.new(answer(OK)), print: true)
    assert_equal 0, run(env)
    assert_equal "feat: add thing\n\nbecause\n", out.string
    assert_empty prompts
    refute(git.calls.any? { |c| c[1] == :commit })

    git = FakeGit.new(staged: ["a.py"])
    env, _, err, prompts = fake_env(git: git, claude: FakeClaude.new(answer(OK)), yes: true, verbose: 1)
    assert_equal 0, run(env)
    assert_empty prompts
    assert_includes git.calls, [:real, :commit, "feat: add thing\n\nbecause"]
    assert_match(/^\[auto-commit\] resolved: all=false yes=true print=false model=#{DEFAULT_MODEL} variant=#{DEFAULT_VARIANT}$/, err.string)
    assert_match(/^\[auto-commit\] committed\.$/, err.string)
  end

  test "read_reply: bytes in, text out, nil at eof" do
    reply = read_reply(StringIO.new("\xFF\n".b))
    assert reply.valid_encoding?
    refute accepts?(reply)
    assert_equal "y\n", read_reply(StringIO.new("y\n"))
    assert_nil read_reply(StringIO.new(""))
  end

  test "run: declined, eof and ctrl+c at the question" do
    [["n\n", 1, ""], [nil, 130, "\n"], [Interrupt, 130, "\n"]].each do |reply, code, tail|
      git = FakeGit.new(staged: ["a.py"])
      env, out, err = fake_env(git: git, claude: FakeClaude.new(answer(OK)), replies: [reply])
      assert_equal code, run(env), reply.inspect
      assert out.string.end_with?("because\n\n#{tail}"), reply.inspect
      assert_equal "[auto-commit] aborted.\n", err.string
      refute(git.calls.any? { |c| c[1] == :commit })
    end
  end

  test "run: nothing staged vs nothing to commit" do
    env, _, err = fake_env(git: FakeGit.new(unstaged: ["a.py"]))
    assert_equal 1, run(env)
    assert_equal "[auto-commit] nothing staged. `git add` what you want committed, or pass -a to stage everything.\n", err.string
    env, _, err = fake_env(git: FakeGit.new)
    assert_equal 1, run(env)
    assert_equal "[auto-commit] working tree clean; nothing to commit.\n", err.string
    env, _, err = fake_env(git: FakeGit.new, all: true)
    assert_equal 1, run(env)
    assert_equal "[auto-commit] working tree clean; nothing to commit.\n", err.string
  end

  test "run: binary files are named, not sent" do
    git = FakeGit.new(staged: ["z.bin", "a.py", "b.png"], binary: ["z.bin", "b.png"], diff: "d")
    claude = FakeClaude.new(answer(OK))
    env, _, err = fake_env(git: git, claude: claude, print: true)
    assert_equal 0, run(env)
    assert_equal "[auto-commit] 2 binary file(s) staged; only filenames will be sent: b.png, z.bin\n", err.string
    assert_includes git.calls, [:real, :staged_diff]
  end

  test "run: -a stages on a copy until confirmed" do
    git = FakeGit.new(staged: ["a.py"], unstaged: ["new.py"])
    env, _, _, prompts = fake_env(git: git, claude: FakeClaude.new(answer(OK)), all: true, replies: ["n"])
    assert_equal 1, run(env)
    assert_equal 1, prompts.size
    assert_equal [[:real, :preview], [:preview, :add_all]], git.calls.select { |c| %i[preview add_all].include?(c[1]) }
    assert_equal ["a.py"], git.staged_files

    git = FakeGit.new(staged: ["a.py"], unstaged: ["new.py"])
    env, = fake_env(git: git, claude: FakeClaude.new(answer(OK)), all: true, yes: true)
    assert_equal 0, run(env)
    tail = git.calls.drop_while { |c| c[0] == :preview || %i[check_repo preview].include?(c[1]) }
    assert_equal [[:real, :add_all], [:real, :commit, "feat: add thing\n\nbecause"]], tail
  end

  test "run: outside a repo, -a or not" do
    [false, true].each do |all|
      git = FakeGit.new(errors: { check_repo: GitError.new("git rev-parse --git-dir failed: fatal: not a git repository") })
      env, _, err = fake_env(git: git, all: all)
      assert_equal 2, run(env)
      assert_equal "[auto-commit] git rev-parse --git-dir failed: fatal: not a git repository\n", err.string
      assert_equal [[:real, :check_repo]], git.calls
    end
  end

  test "run: model and git failures map to exit codes" do
    env, out, err = fake_env(git: FakeGit.new(staged: ["a.py"]), claude: FakeClaude.new(raise_after: GenerateCancelled.new("aborted")))
    assert_equal 130, run(env)
    assert_equal "\n", out.string
    assert_equal "[auto-commit] aborted.\n", err.string

    env, _, err = fake_env(git: FakeGit.new(staged: ["a.py"]), claude: FakeClaude.new(answer({ "tag" => "nope", "message" => "x" })))
    assert_equal 1, run(env)
    assert_equal "[auto-commit] invalid tag from model: \"nope\"\n", err.string

    env, _, err = fake_env(git: FakeGit.new(errors: { staged_name_status: GitError.new("git diff failed: boom") }))
    assert_equal 2, run(env)
    assert_equal "[auto-commit] git diff failed: boom\n", err.string

    git = FakeGit.new(staged: ["a.py"], errors: { commit: GitError.new("git commit failed: hook said no") })
    env, _, err = fake_env(git: git, claude: FakeClaude.new(answer(OK)), yes: true)
    assert_equal 2, run(env)
    assert_equal "[auto-commit] git commit failed: hook said no\n", err.string
  end

  # --- real git ---

  test "git: staged diff from a nested directory" do
    in_repo do |dir|
      File.write("file.txt", "staged content\n")
      sh("git", "add", "--", "file.txt")
      Dir.mkdir("nested")
      Dir.chdir(File.join(dir, "nested")) do
        git = Git.new
        assert_equal ["file.txt"], git.staged_files
        assert_includes git.staged_diff, "staged content"
      end
    end
  end

  test "git: non-ascii paths come back unquoted" do
    name = "caf#{[0xE9].pack("U")}.txt"
    in_repo do
      File.write(name, "staged content\n")
      sh("git", "add", "--", name)
      git = Git.new
      assert_equal [name], git.staged_files
      assert_includes git.staged_diff, "staged content"
      assert_equal({ name => "A" }, git.staged_name_status)
    end
  end

  test "git: worktree_dirty? when nothing is staged" do
    in_repo do
      File.write("file.txt", "committed\n")
      sh("git", "add", "--", "file.txt")
      fixture_commit("chore: init")
      git = Git.new
      assert_empty git.staged_files
      refute git.worktree_dirty?
      File.write("file.txt", "edited\n")
      assert git.worktree_dirty?
      File.write("file.txt", "committed\n")
      File.write("untracked.txt", "new\n")
      assert git.worktree_dirty?
    end
  end

  test "git: preview leaves the real index alone" do
    in_repo do
      File.write("tracked.txt", "committed\n")
      File.write(".gitignore", "kept.log\n")
      File.write("kept.log", "tracked despite the ignore\n")
      sh("git", "add", "--", "tracked.txt", ".gitignore")
      sh("git", "add", "-f", "--", "kept.log")
      fixture_commit("chore: init")
      File.write("tracked.txt", "edited\n")
      File.write("untracked.txt", "new\n")
      before = sh("git", "status", "--porcelain")
      git = Git.new
      git.preview do |copy|
        copy.add_all
        # an empty index would lose kept.log: add -A never re-adds an ignored file.
        assert_equal({ "tracked.txt" => "M", "untracked.txt" => "A" }, copy.staged_name_status)
      end
      assert_empty git.staged_files
      assert_equal before, sh("git", "status", "--porcelain")
    end
  end

  test "git: preview in a repo with no index file yet" do
    in_repo do
      File.write("first.txt", "new\n")
      refute File.exist?(".git/index")
      Git.new.preview do |copy|
        copy.add_all
        assert_equal ["first.txt"], copy.staged_files
      end
      assert_empty Git.new.staged_files
      refute File.exist?(".git/index")
    end
  end

  test "git: a rename diffs as a rename, not as a fresh add" do
    in_repo do
      File.write("old.txt", "x\n")
      sh("git", "add", "--", "old.txt")
      fixture_commit("chore: init")
      sh("git", "mv", "old.txt", "new.txt")
      diff = Git.new.staged_diff
      assert_includes diff, "rename from old.txt\nrename to new.txt"
      refute_includes diff, "new file mode"
    end
  end

  test "git: a non-utf8 path still gets its diff" do
    in_repo do
      blob = sh("git", "hash-object", "-w", "--stdin", stdin: "raw bytes\n").strip
      # straight into the index: some filesystems won't hold a name like this.
      sh("git", "update-index", "--add", "--cacheinfo", "100644,#{blob},caf\xE9.txt".b)
      git = Git.new
      assert_equal ["caf#{[0xFFFD].pack("U")}.txt"], git.staged_files
      assert_includes git.staged_diff, "+raw bytes"
    end
  end

  test "git: renames and binaries parsed from the real thing" do
    in_repo do
      File.write("old.txt", "x\n")
      sh("git", "add", "--", "old.txt")
      fixture_commit("chore: init")
      sh("git", "mv", "old.txt", "new.txt")
      File.binwrite("blob.dat", "\x00\x01\x02")
      sh("git", "add", "--", "blob.dat")
      git = Git.new
      assert_equal ["blob.dat"], git.staged_binary_files
      assert_equal({ "new.txt" => "R", "blob.dat" => "A" }, git.staged_name_status)
    end
  end

  test "git: a NUL in an argument is a GitError, not a crash" do
    in_repo do
      e = assert_raises(GitError) { Git.new.commit("fix: a\0b") }
      assert_match(/\Agit commit failed: .*null byte/, e.message)
    end
  end

  test "git: outside a repo, check_repo says so in one line" do
    in_tmpdir do |dir|
      git = Git.new(cwd: dir)
      e = assert_raises(GitError) { git.check_repo }
      assert_match(/\Agit rev-parse --git-dir failed: fatal: not a git repository/, e.message)
      assert_equal 1, e.message.lines.size
    end
    in_repo { assert_nil Git.new.check_repo }
  end

  # --- real claude stand-in ---

  test "claude: runs the binary with the args, returns its stderr" do
    in_tmpdir do |dir|
      bin = fake_claude_bin(dir, "echo line1; echo line2; echo warned >&2")
      lines = []
      assert_equal "warned", Claude.new(bin: bin).run(%w[--print x]) { |l| lines << l }
      assert_equal ["line1\n", "line2\n"], lines
      assert_equal "--print\nx\n", File.read(File.join(dir, "argv"))
    end
  end

  test "claude: failure, timeout, missing binary" do
    in_tmpdir do |dir|
      bin = fake_claude_bin(dir, "echo boom >&2; exit 3")
      e = assert_raises(GenerateError) { Claude.new(bin: bin).run([]) {} }
      assert_equal "claude cli failed (rc=3): boom", e.message

      bin = fake_claude_bin(dir, "exec sleep 5")
      assert_quick do
        e = assert_raises(GenerateError) { Claude.new(bin: bin, timeout: 0.2).run([]) {} }
        assert_equal "claude cli timed out after 0.2s", e.message
      end

      # stdout closed but the process lingers: the timeout still has to cover the wait.
      bin = fake_claude_bin(dir, "exec >&-; exec sleep 5")
      assert_quick do
        e = assert_raises(GenerateError) { Claude.new(bin: bin, timeout: 0.2).run([]) {} }
        assert_equal "claude cli timed out after 0.2s", e.message
      end

      e = assert_raises(GenerateError) { Claude.new(bin: File.join(dir, "nope")).run([]) {} }
      assert_match(/nope` cli not found on PATH\z/, e.message)

      bin = fake_claude_bin(dir, "kill -9 $$")
      e = assert_raises(GenerateError) { Claude.new(bin: bin).run([]) {} }
      assert_equal "claude cli failed (rc=-9): ", e.message
    end
  end

  test "claude: a raising reader still kills the child" do
    in_tmpdir do |dir|
      bin = fake_claude_bin(dir, "echo started; exec sleep 5")
      assert_quick do
        assert_raises(Errno::EPIPE) { Claude.new(bin: bin).run([]) { |_| raise Errno::EPIPE } }
      end
    end
  end

  test "claude: ctrl+c mid-stream cancels and reaps" do
    in_tmpdir do |dir|
      bin = fake_claude_bin(dir, "echo started; exec sleep 5")
      main = Thread.current
      assert_quick do
        e = assert_raises(GenerateCancelled) do
          Claude.new(bin: bin).run([]) { |_| Thread.new { sleep 0.1; main.raise(Interrupt) } }
        end
        assert_equal "aborted", e.message
      end
      assert_raises(Errno::ECHILD) { Process.wait(-1, Process::WNOHANG) }
    end
  end

  # --- end to end ---

  test "e2e: stand-in claude, real repo, real commit" do
    in_repo do |dir|
      File.write("hello.txt", "hello\n")
      sh("git", "add", "--", "hello.txt")
      bin = fake_claude_bin(dir, "cat <<'EOF'\n#{answer({ "tag" => "feat", "message" => "greet the world" }).join("\n")}\nEOF")
      cfg = default_cfg.merge(yes: true)
      out = StringIO.new
      env = Env.new(git: Git.new, claude: Claude.new(bin: bin), log: Log.new(io: StringIO.new),
                    cfg: cfg, out: out, input: ->(_) { flunk "asked" })
      assert_equal 0, run(env)
      assert_equal "feat: greet the world\n\n", out.string
      assert_equal "feat: greet the world\n", sh("git", "log", "-1", "--format=%B").sub(/\n+\z/, "\n")
      argv = File.read(File.join(dir, "argv"))
      assert_includes argv, "--json-schema"
      assert_includes argv, "  hello.txt (added)"
      assert_includes argv, "+hello"
    end
  end

  # --- runner ---

  def self_test
    color = $stdout.tty? && !ENV.key?("NO_COLOR")
    paint = ->(code, str) { color ? sgr(code, str) : str }
    failures = 0
    TESTS.each do |name, blk|
      print "#{name} ... "
      SelfTest.new.instance_exec(&blk)
      puts paint.call("32", "pass")
    rescue Minitest::Assertion, StandardError => e
      failures += 1
      puts paint.call("31", "fail")
      detail = e.is_a?(Minitest::Assertion) ? e.message : "#{e.class}: #{e.message}\n#{e.backtrace.first}"
      puts detail.gsub(/^/, "    ")
    end

    if failures.zero?
      puts paint.call("32", "self-test passed (#{TESTS.size})")
    else
      puts paint.call("31", "self-test failed (#{failures}/#{TESTS.size})")
    end
    failures.zero?
  end
end

ARGV.first == "--test" ? exit(self_test) : main(ARGV)
