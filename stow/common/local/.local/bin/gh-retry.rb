#!/usr/bin/env ruby
# frozen_string_literal: true

# gh-retry -- rerun failed gh actions runs, optionally gated on log patterns.
#
# watches one or more runs in parallel; when one fails, reruns just its failed
# jobs. if patterns are given, only reruns when one of them appears in the
# failed-job logs (i.e. the failure looks transient). loops up to N times per
# run with a delay between attempts.
#
# shells out to the user's `gh`. the decisions are pure functions; everything
# with side effects (gh, time, output) comes in through an Env, which
# `gh-retry --test` swaps for fakes to run the built-in self-test.

require "optparse"
require "json"
require "open3"

# clean ctrl+c: don't dump the open3 reader-thread backtrace.
Thread.report_on_exception = false

# --- command line -----------------------------------------------------------

class UsageError < StandardError; end

def default_cfg
  { retries: 3, delay: 30, poll: 10,
    timeout: 0, # 0 = no overall deadline
    patterns: [], stop_patterns: [], ignore_case: false, cancel: false, dry_run: false }
end

def option_parser(cfg)
  OptionParser.new do |o|
    o.banner = <<~USAGE
      usage: gh-retry [options] <target>... [-- pattern...]

      watch gh actions runs; on failure, rerun the failed jobs. if patterns are
      given, only rerun when one appears in the failed logs. always reruns failed
      jobs only (never the whole run). several targets are watched in parallel
      and share the patterns; "--" separates the targets from the patterns.

      <target> identifies a run (need not live in the current repo), either as
        OWNER/REPO/RUN_ID          e.g. canonical/chisel-releases/29429492601
      or a github url (anything with .../actions/runs/RUN_ID in it), e.g.
        https://github.com/canonical/chisel-releases/actions/runs/29429492601/job/8756?pr=1046
      or a pull request (latest failed actions run on that PR; else the latest run):
        https://github.com/canonical/sd-tools/pull/4261
        canonical/sd-tools#4261

      examples:
        gh-retry canonical/chisel-releases/29429492601
        gh-retry canonical/chisel-releases/29429492601 -- \\
                 "context deadline exceeded (Client.Timeout exceeded while awaiting headers)" \\
                 "error: cannot talk to archive:"
        gh-retry canonical/chisel-releases#1191 canonical/chisel-releases#1192 -- \\
                 "error: cannot talk to archive:"

      options:
    USAGE

    o.on("-N", "--retries N", Integer, "max reruns after first failure (default #{cfg[:retries]}); -9 is short for -N 9") { |v| cfg[:retries] = v }
    o.on("-d", "--delay SECONDS", Integer, "delay between reruns (default #{cfg[:delay]})") { |v| cfg[:delay] = v }
    o.on("-p", "--poll SECONDS", Integer, "status poll interval while watching (default #{cfg[:poll]})") { |v| cfg[:poll] = v }
    o.on("-t", "--timeout SECONDS", Integer, "overall wall-clock deadline; abort if exceeded, e.g. when a job wedges in_progress (default: none)") { |v| cfg[:timeout] = v }
    o.on("-s", "--stop-on PATTERN", "give up immediately if PATTERN appears in the failed logs, even if a retry pattern also matches (repeatable)") { |v| cfg[:stop_patterns] << v }
    o.on("-i", "--ignore-case", "case-insensitive pattern matching") { cfg[:ignore_case] = true }
    o.on("-c", "--cancel", "if nothing is running but queued jobs keep the run open, cancel it to force a rerun (gh can't rerun an in-progress run)") { cfg[:cancel] = true }
    o.on("-n", "--dry-run", "watch and report what would happen, but stop before the first write action (rerun/cancel)") { cfg[:dry_run] = true }
    o.on("-h", "--help", "show this help") do
      puts o
      exit 0
    end
  end
end

# returns [cfg, targets]; raises UsageError on a bad command line. --help
# prints and exits straight away.
def parse_args(argv)
  cfg = default_cfg
  parser = option_parser(cfg)
  argv = argv.dup

  # everything after "--" is a pattern, kept verbatim: split before option
  # parsing so neither OptionParser nor the -9 rewrite below touches it.
  sep = argv.index("--")
  cfg[:patterns] = sep ? argv.slice!(sep..).drop(1) : []

  # -9 means -N 9 (same idea as nice/kill numeric shorts).
  argv = argv.flat_map { |arg| arg =~ /\A-(\d+)\z/ ? ["-N", $1] : [arg] }
  parser.parse!(argv)
  raise UsageError, parser.to_s if argv.empty?

  targets = argv.map do |target|
    parse_target(target) or
      raise UsageError, "gh-retry: could not parse target #{target.inspect} -- expected OWNER/REPO/RUN_ID, a github run url, or a pull request"
  end
  [cfg, targets]
end

# parse a target into [:run, repo, run_id] or [:pr, repo, number].
# run forms: OWNER/REPO/RUN_ID, or a url containing .../actions/runs/RUN_ID.
# pr forms:  OWNER/REPO#N, OWNER/REPO/pull/N, or a .../pull/N url.
def parse_target(target)
  if target =~ %r{github\.com/([^/]+)/([^/]+)/actions/runs/(\d+)}
    [:run, "#{$1}/#{$2}", $3]
  elsif target =~ %r{github\.com/([^/]+)/([^/]+)/pull/(\d+)}
    [:pr, "#{$1}/#{$2}", $3]
  elsif target =~ %r{\A([^/\s]+)/([^/\s]+)#(\d+)\z}
    [:pr, "#{$1}/#{$2}", $3]
  elsif target =~ %r{\A([^/\s]+)/([^/\s]+)/pull/(\d+)\z}
    [:pr, "#{$1}/#{$2}", $3]
  elsif target =~ %r{\A([^/\s]+)/([^/\s]+)/(\d+)\z}
    [:run, "#{$1}/#{$2}", $3]
  end
end

# --- output -----------------------------------------------------------------

# basic 8-color SGR only (30-37). bold black is the usual terminal gray;
# no 256-color (38;5;N) and no aixterm brights (90-97).
def sgr(code, str, bold: false)
  "\e[#{bold ? "1;#{code}" : code}m#{str}\e[0m"
end

def status_code(status)
  case status
  when "success", "neutral" then "32"
  when "failure", "cancelled", "timed_out", "startup_failure", "action_required" then "31"
  when "in_progress", "queued", "pending", "waiting" then "33"
  when "skipped" then "30"
  end
end

# with several targets each watcher gets its own labelled Log so the
# interleaved lines can be told apart.
class Log
  def initialize(io:, label: nil, color: false)
    @io = io
    @label = label
    @color = color
  end

  def with_label(label)
    Log.new(io: @io, label: label, color: @color)
  end

  def info(msg) line("34", msg) end # blue
  def good(msg) line("32", msg) end # green
  def warn(msg) line("33", msg) end # yellow
  def bad(msg)  line("31", msg) end # red

  def plain(msg)
    @io.write("#{msg}\n")
  end

  # bold so black reads as gray; the prefix stays unbolded.
  def status(status)
    code = status_code(status)
    code ? paint(code, status, bold: true) : status
  end

  private

  def paint(code, str, bold: false)
    @color ? sgr(code, str, bold: bold) : str
  end

  # one write per line so lines from parallel watchers don't interleave.
  def line(code, msg)
    tag = @label ? "[gh-retry #{@label}] " : "[gh-retry] "
    @io.write("#{paint(code, tag)}#{msg}\n")
  end
end

# --- side effects -----------------------------------------------------------

class GhError < StandardError; end

# the user's gh. every call names its repo, so runs need not live in the
# current one.
class Gh
  def run_state(repo, run_id)
    json(repo, "run", "view", run_id, "--json", "status,conclusion,jobs")
  end

  def pr_rollup(repo, number)
    json(repo, "pr", "view", number, "--json", "statusCheckRollup")["statusCheckRollup"] || []
  end

  # whatever gh printed, success or not; empty means not there (yet).
  def failed_logs(repo, run_id)
    Open3.capture2e("gh", "run", "view", run_id, "--log-failed", "--repo", repo).first
  end

  def rerun(repo, run_id)
    system("gh", "run", "rerun", run_id, "--failed", "--repo", repo)
  end

  def cancel(repo, run_id)
    system("gh", "run", "cancel", run_id, "--repo", repo)
  end

  private

  def json(repo, *args)
    out, status = Open3.capture2e("gh", *args, "--repo", repo)
    raise GhError, out unless status.success?

    JSON.parse(out)
  rescue JSON::ParserError => e
    raise GhError, "#{e.message}\n#{out}"
  end
end

class Clock
  def now
    Time.now
  end

  def sleep(seconds)
    Kernel.sleep(seconds)
  end
end

Env = Struct.new(:gh, :clock, :log, :cfg, keyword_init: true)

# --- decisions --------------------------------------------------------------

def job_counts(data)
  jobs = data["jobs"] || []
  [jobs.count { |j| j["status"] == "in_progress" },
   jobs.count { |j| j["status"] == "completed" && j["conclusion"] == "failure" }]
end

# what a run's state means for the watcher:
#   :success  -- run completed, all green
#   :retry    -- run completed with failures; safe to rerun --failed now
#   :cancel   -- (cancel mode only) nothing running + failures, but queued jobs
#                keep the run in_progress; caller must cancel to force a rerun
#   :waiting  -- still going, poll again
#   <other>   -- run completed, not green, nothing failed to rerun (give up)
# note: gh refuses to rerun a run that isn't `completed`, so by default we wait
# for completion.
def classify_run(data, cancel: false)
  running, failed = job_counts(data)
  if data["status"] == "completed"
    return :success if data["conclusion"] == "success"
    return :retry if failed.positive?

    return data["conclusion"] || "unknown"
  end
  return :cancel if cancel && running.zero? && failed.positive?

  :waiting
end

# a pull request is not a run. pick one actions run from its checks: a failed
# one if any (latest by completed/started time), otherwise the latest run so
# the watcher can wait or report success. returns {id:, others:, checks:},
# where others are the failed runs not picked, or nil if there are no runs.
def pick_pr_run(rollup)
  runs = {}
  rollup.each do |check|
    url = check["detailsUrl"] || check["targetUrl"] || ""
    next unless url =~ %r{/actions/runs/(\d+)}

    id = $1
    stamp = check["completedAt"] || check["startedAt"] || ""
    entry = runs[id] ||= { id: id, stamp: stamp, failed: false, checks: [] }
    entry[:stamp] = stamp if stamp > entry[:stamp]
    conclusion = check["conclusion"].to_s.downcase
    status = conclusion.empty? ? check["status"].to_s.downcase : conclusion
    status = "unknown" if status.empty?
    entry[:checks] << [check["name"], status] if check["name"]
    entry[:failed] = true if %w[failure cancelled timed_out].include?(conclusion)
  end
  return nil if runs.empty?

  failed = runs.values.select { |r| r[:failed] }
  chosen = (failed.empty? ? runs.values : failed).max_by { |r| r[:stamp] }
  { id: chosen[:id], others: failed.map { |r| r[:id] } - [chosen[:id]], checks: chosen[:checks].uniq }
end

def match_pattern(logs, patterns, ignore_case)
  hay = ignore_case ? logs.downcase : logs
  patterns.find do |p|
    needle = ignore_case ? p.downcase : p
    hay.include?(needle)
  end
end

# what the failed logs say about a failure:
#   [:unclassified]        -- no logs to read
#   [:stop, pattern]       -- a stop-on pattern matched: a real failure
#   [:no_match]            -- retry patterns given, none matched: not transient
#   [:rerun, pattern|nil]  -- transient, or no retry patterns to check
# deny-list wins: a stop-on match means a real failure even if a retry pattern
# also matches somewhere in the noisy log.
def verdict(logs, patterns, stop_patterns, ignore_case)
  return [:unclassified] if logs.strip.empty?

  stop = match_pattern(logs, stop_patterns, ignore_case)
  return [:stop, stop] if stop
  return [:rerun, nil] if patterns.empty?

  matched = match_pattern(logs, patterns, ignore_case)
  matched ? [:rerun, matched] : [:no_match]
end

# --- gh with retries --------------------------------------------------------

# raised when a target cannot be watched any further; the watcher prints the
# message and marks the target as given up.
class GiveUp < StandardError; end

# querying the run can itself hit a transient gh/network/api failure. since the
# whole point of this tool is riding out flaky infra, don't let a single bad
# poll abort the watch -- retry a few times before giving up.
POLL_QUERY_RETRIES = 5
POLL_QUERY_BACKOFF = 5 # seconds between failed-poll retries

# `gh run view --log-failed` can come back empty right after a run completes,
# before the logs have materialised. retry a few times so we don't mistake
# "logs not ready yet" for "no pattern matched".
LOG_FETCH_RETRIES = 4
LOG_FETCH_BACKOFF = 5 # seconds between empty-log retries

# after `gh run rerun --failed`, gh keeps the same run id but takes a few
# seconds to flip status away from completed. if we loop straight back into
# wait_for_actionable it can observe the stale completed/failure state and fire
# a second rerun immediately, burning an attempt. block until the run actually
# leaves completed (or a bounded number of polls elapse) before trusting it.
RESTART_POLLS = 12

# calls the block until it returns non-nil, retrying up to `tries` times with
# `backoff` seconds between. returns nil when the retries run out.
def with_retries(env, tries, backoff, what)
  attempts = 0
  loop do
    result = yield
    return result unless result.nil?

    attempts += 1
    return nil if attempts > tries

    env.log.warn "#{what} (attempt #{attempts}/#{tries}), retrying in #{backoff}s"
    env.clock.sleep backoff
  end
end

def state_for(env, repo, run_id)
  err = nil
  state = with_retries(env, POLL_QUERY_RETRIES, POLL_QUERY_BACKOFF, "poll failed") do
    env.gh.run_state(repo, run_id)
  rescue GhError => e
    err = e
    nil
  end
  state or raise GiveUp, "failed to query run #{run_id} after #{POLL_QUERY_RETRIES} retries:\n#{err.message}"
end

def failed_logs(env, repo, run_id)
  logs = with_retries(env, LOG_FETCH_RETRIES, LOG_FETCH_BACKOFF, "failed logs empty") do
    out = env.gh.failed_logs(repo, run_id)
    out unless out.strip.empty?
  end
  logs || ""
end

def resolve_pr_run(env, repo, number)
  log = env.log
  rollup = begin
    env.gh.pr_rollup(repo, number)
  rescue GhError => e
    raise GiveUp, "failed to look up #{repo}##{number}:\n#{e.message}"
  end
  pick = pick_pr_run(rollup) or raise GiveUp, "no actions runs found on #{repo}##{number}"

  unless pick[:others].empty?
    log.warn "#{repo}##{number} has other failed runs (#{pick[:others].join(", ")}); watching #{pick[:id]}"
  end
  log.info "resolved #{repo}##{number} -> run #{pick[:id]}"
  pick[:checks].each { |name, status| log.info "  #{name}  #{log.status(status)}" }
  pick[:id]
end

# polls until classify_run says something other than :waiting, or :timeout
# once the deadline (a Time, or nil for none) passes -- catches a job that
# wedges in_progress and never completes.
def wait_for_actionable(env, repo, run_id, deadline)
  poll = env.cfg[:poll]
  last = nil
  loop do
    data = state_for(env, repo, run_id)
    state = classify_run(data, cancel: env.cfg[:cancel])
    return state unless state == :waiting
    return :timeout if deadline && env.clock.now >= deadline

    running, failed = job_counts(data)
    label = "#{data['status']} (#{running} running, #{failed} failed)"
    if label != last
      env.log.info "status: #{label}"
      env.log.info "rechecking every #{poll}s ..."
      last = label
    end
    env.clock.sleep poll
  end
end

def wait_until_restarted(env, repo, run_id)
  RESTART_POLLS.times do
    return true if state_for(env, repo, run_id)["status"] != "completed"

    env.clock.sleep env.cfg[:poll]
  end
  env.log.warn "run #{run_id} still reports completed after rerun -- proceeding anyway"
  false
end

# --- watch ------------------------------------------------------------------

# runs the retry loop for one target. returns true once the run passes (or a
# dry run stops before its first write), false when it gives up.
def watch(env, target)
  cfg = env.cfg
  log = env.log
  retries = cfg[:retries]

  kind, repo, ident = target
  run_id = kind == :pr ? resolve_pr_run(env, repo, ident) : ident

  # first line: the resolved run url, plain and copy-pasteable.
  log.plain "https://github.com/#{repo}/actions/runs/#{run_id}"

  attempts_left = retries
  deadline = cfg[:timeout].positive? ? env.clock.now + cfg[:timeout] : nil

  loop do
    log.info "watching run #{run_id} in #{repo} ..."
    state = wait_for_actionable(env, repo, run_id, deadline)

    if state == :timeout
      log.bad "overall timeout (#{cfg[:timeout]}s) exceeded while waiting on run #{run_id} -- giving up"
      return false
    elsif state == :success
      log.good "run #{run_id} passed"
      return true
    elsif state == :cancel
      if cfg[:dry_run]
        log.good "[dry-run] would cancel run #{run_id} (failures + queued, nothing running), then rerun failed jobs"
        return true
      end
      log.warn "run #{run_id} stalled (failures + queued, nothing running) -- cancelling to force rerun"
      env.gh.cancel(repo, run_id)
      env.clock.sleep cfg[:poll] # let the cancellation propagate before we re-poll
      # loop back; once the run reports completed we can rerun.
      next
    elsif state != :retry
      log.bad "run #{run_id} finished: #{state} -- nothing failed to rerun, giving up"
      return false
    end

    log.warn "run #{run_id} completed with failures"

    unless cfg[:patterns].empty? && cfg[:stop_patterns].empty?
      logs = failed_logs(env, repo, run_id)
      outcome, pattern = verdict(logs, cfg[:patterns], cfg[:stop_patterns], cfg[:ignore_case])
      case outcome
      when :unclassified
        # we can't classify the failure. don't treat "couldn't read the logs"
        # as "not transient"; assume transient and rerun.
        log.warn "failed logs empty/unavailable -- can't classify, assuming transient and rerunning"
      when :stop
        log.bad "stop-on pattern matched: #{pattern.inspect} -- treating as a real failure, giving up"
        return false
      when :no_match
        log.bad "no retry pattern matched failed logs -- not transient, giving up"
        return false
      when :rerun
        log.info "matched pattern: #{pattern.inspect}" if pattern
      end
    end

    if cfg[:dry_run]
      log.good "[dry-run] would rerun failed jobs for run #{run_id} (gh run rerun #{run_id} --failed)"
      return true
    end

    if attempts_left <= 0
      log.bad "retries exhausted (#{retries}) -- giving up"
      return false
    end

    attempts_left -= 1
    attempt = retries - attempts_left
    log.warn "rerunning failed jobs (attempt #{attempt}/#{retries})"

    unless env.gh.rerun(repo, run_id)
      log.bad "gh run rerun failed -- giving up"
      return false
    end

    env.clock.sleep cfg[:delay] if cfg[:delay].positive?
    # don't let the next watch iteration read the pre-rerun completed state.
    wait_until_restarted(env, repo, run_id)
  end
rescue GiveUp => e
  env.log.bad e.message
  false
end

# one watcher thread per target, labelled only when there is more than one.
# returns true iff every target passed.
def watch_all(env, targets)
  multi = targets.size > 1
  threads = targets.map do |target|
    kind, _repo, ident = target
    label = multi ? (kind == :pr ? "##{ident}" : ident) : nil
    target_env = env.dup.tap { |e| e.log = env.log.with_label(label) }
    Thread.new { watch(target_env, target) }
  end
  results = threads.map(&:value)

  if multi
    targets.zip(results).each do |(kind, repo, ident), ok|
      name = kind == :pr ? "#{repo}##{ident}" : "#{repo}/#{ident}"
      ok ? env.log.good("#{name} ok") : env.log.bad("#{name} gave up")
    end
  end
  results.all?
end

# --- main -------------------------------------------------------------------

def main(argv)
  cfg, targets = begin
    parse_args(argv)
  rescue UsageError => e
    warn e.message
    exit 2
  end

  log = Log.new(io: $stderr, color: $stdout.tty? && !ENV.key?("NO_COLOR"))
  Signal.trap("INT") do
    $stderr.write("\n")
    log.warn "interrupted"
    exit 130
  end

  env = Env.new(gh: Gh.new, clock: Clock.new, log: log, cfg: cfg)
  exit(watch_all(env, targets) ? 0 : 1)
end

# --- self-test (gh-retry --test) --------------------------------------------

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

  # replays canned answers per run id / PR number. the last answer in each
  # queue repeats, so a test only scripts the transitions. an Exception in a
  # queue is raised instead of returned.
  class FakeGh
    attr_reader :writes

    def initialize(states: {}, logs: {}, rollups: {}, rerun_ok: true)
      @states = states
      @logs = logs
      @rollups = rollups
      @rerun_ok = rerun_ok
      @writes = []
    end

    def run_state(_repo, run_id) answer(@states, run_id) end
    def failed_logs(_repo, run_id) answer(@logs, run_id) end
    def pr_rollup(_repo, number) answer(@rollups, number) end

    def rerun(_repo, run_id)
      @writes << [:rerun, run_id]
      @rerun_ok
    end

    def cancel(_repo, run_id)
      @writes << [:cancel, run_id]
      true
    end

    private

    def answer(table, key)
      queue = table.fetch(key)
      item = queue.size > 1 ? queue.shift : queue.first
      raise item if item.is_a?(Exception)

      item
    end
  end

  # sleeping advances the clock, so deadlines play out instantly. a day of fake
  # sleep means a loop that never ends; fail it rather than hang.
  class FakeClock
    attr_reader :now, :slept

    def initialize
      @now = Time.at(0)
      @slept = 0
    end

    def sleep(seconds)
      @now += seconds
      @slept += seconds
      raise "fake clock ran away" if @slept > 86_400
    end
  end

  def fake_env(gh, **cfg)
    io = StringIO.new
    cfg = default_cfg.merge(delay: 0, poll: 1).merge(cfg)
    [Env.new(gh: gh, clock: FakeClock.new, log: Log.new(io: io), cfg: cfg), io]
  end

  def job(status, conclusion = nil)
    { "status" => status, "conclusion" => conclusion }
  end

  def run_data(status, conclusion = nil, jobs = [])
    { "status" => status, "conclusion" => conclusion, "jobs" => jobs }
  end

  def rollup_check(name, run_id, conclusion, at, url_key: "detailsUrl")
    { "name" => name, url_key => "https://github.com/o/r/actions/runs/#{run_id}/job/1",
      "conclusion" => conclusion, "completedAt" => at }
  end

  PASSED = run_data("completed", "success", [job("completed", "success")])
  FAILED = run_data("completed", "failure", [job("completed", "failure"), job("completed", "success")])
  RUNNING = run_data("in_progress", nil, [job("in_progress")])
  STALLED = run_data("in_progress", nil, [job("completed", "failure"), job("queued")])

  # --- pure ---

  test "parse_target: run and pr forms" do
    {
      "o/r/123" => [:run, "o/r", "123"],
      "https://github.com/o/r/actions/runs/123/job/9?pr=1" => [:run, "o/r", "123"],
      "o/r#7" => [:pr, "o/r", "7"],
      "o/r/pull/7" => [:pr, "o/r", "7"],
      "https://github.com/o/r/pull/7/checks" => [:pr, "o/r", "7"],
    }.each { |input, want| assert_equal want, parse_target(input), input }
    ["o/r", "o/r/x", "123", "o r/1"].each { |junk| assert_nil parse_target(junk), junk }
  end

  test "parse_args: -9 and verbatim patterns" do
    cfg, targets = parse_args(%w[-9 o/r/1 o/r#2 -- -3 --retries])
    assert_equal 9, cfg[:retries]
    assert_equal 30, cfg[:delay]
    assert_equal [[:run, "o/r", "1"], [:pr, "o/r", "2"]], targets
    assert_equal %w[-3 --retries], cfg[:patterns]
  end

  test "parse_args: repeatable stop-on, fresh defaults per call" do
    cfg, = parse_args(%w[-s a --stop-on b o/r/1])
    assert_equal %w[a b], cfg[:stop_patterns]
    cfg, = parse_args(%w[o/r/1])
    assert_empty cfg[:stop_patterns]
  end

  test "parse_args: usage errors" do
    assert_raises(UsageError) { parse_args([]) }
    assert_raises(UsageError) { parse_args(%w[-- pattern]) }
    e = assert_raises(UsageError) { parse_args(%w[o/r/1 junk]) }
    assert_match(/could not parse target "junk"/, e.message)
  end

  test "match_pattern: case and order" do
    logs = "Error: Cannot talk to archive\ntimeout"
    assert_nil match_pattern(logs, ["cannot talk"], false)
    assert_equal "cannot talk", match_pattern(logs, ["cannot talk"], true)
    assert_equal "timeout", match_pattern(logs, %w[nope timeout Error], false)
    assert_nil match_pattern(logs, [], false)
  end

  test "classify_run" do
    assert_equal :success, classify_run(PASSED)
    assert_equal :retry, classify_run(FAILED)
    assert_equal "cancelled", classify_run(run_data("completed", "cancelled", [job("completed", "cancelled")]))
    assert_equal "unknown", classify_run(run_data("completed"))
    assert_equal :waiting, classify_run(RUNNING)
    assert_equal :waiting, classify_run(STALLED)
    assert_equal :cancel, classify_run(STALLED, cancel: true)
    still_running = run_data("in_progress", nil, [job("in_progress"), job("completed", "failure")])
    assert_equal :waiting, classify_run(still_running, cancel: true)
  end

  test "pick_pr_run: latest failed run wins" do
    pick = pick_pr_run([
      rollup_check("a", 1, "FAILURE", "2026-01-01"),
      rollup_check("b", 2, "SUCCESS", "2026-01-03"),
      rollup_check("c", 3, "FAILURE", "2026-01-02"),
      rollup_check("d", 3, "SUCCESS", "2026-01-02"),
      rollup_check("d", 3, "SUCCESS", "2026-01-02"),
    ])
    assert_equal "3", pick[:id]
    assert_equal ["1"], pick[:others]
    assert_equal [%w[c failure], %w[d success]], pick[:checks]
  end

  test "pick_pr_run: no failures picks the latest run" do
    pending = rollup_check("b", 2, "", "2026-01-02", url_key: "targetUrl").merge("status" => "IN_PROGRESS")
    pick = pick_pr_run([rollup_check("a", 1, "SUCCESS", "2026-01-01"), pending])
    assert_equal({ id: "2", others: [], checks: [%w[b in_progress]] }, pick)
  end

  test "pick_pr_run: nothing from actions" do
    assert_nil pick_pr_run([])
    assert_nil pick_pr_run([{ "name" => "lint", "detailsUrl" => "https://ci.example.com/1" }])
  end

  test "verdict" do
    assert_equal [:stop, "fatal"], verdict("flaky\nfatal", ["flaky"], ["fatal"], false)
    assert_equal [:rerun, "flaky"], verdict("flaky", ["flaky"], ["fatal"], false)
    assert_equal [:no_match], verdict("boom", ["flaky"], [], false)
    assert_equal [:rerun, nil], verdict("boom", [], ["fatal"], false)
    assert_equal [:unclassified], verdict(" \n", ["flaky"], ["fatal"], false)
  end

  test "log: labels and colour" do
    io = StringIO.new
    Log.new(io: io).info("hi")
    Log.new(io: io).with_label("#7").bad("no")
    Log.new(io: io, color: true).good("ok")
    assert_equal "[gh-retry] hi\n[gh-retry #7] no\n\e[32m[gh-retry] \e[0mok\n", io.string
    assert_equal "skipped", Log.new(io: io).status("skipped")
    assert_equal "\e[1;30mskipped\e[0m", Log.new(io: io, color: true).status("skipped")
    assert_equal "weird", Log.new(io: io, color: true).status("weird")
  end

  # --- gh with retries ---

  test "state_for: rides out transient gh failures" do
    gh = FakeGh.new(states: { "1" => [GhError.new("502"), GhError.new("502"), PASSED] })
    env, io = fake_env(gh)
    assert_equal PASSED, state_for(env, "o/r", "1")
    assert_equal 2, io.string.scan(/poll failed/).size
    assert_equal 2 * POLL_QUERY_BACKOFF, env.clock.slept
  end

  test "state_for: gives up after POLL_QUERY_RETRIES" do
    env, = fake_env(FakeGh.new(states: { "1" => [GhError.new("502")] }))
    e = assert_raises(GiveUp) { state_for(env, "o/r", "1") }
    assert_equal "failed to query run 1 after #{POLL_QUERY_RETRIES} retries:\n502", e.message
  end

  test "failed_logs: waits for logs to materialise" do
    env, = fake_env(FakeGh.new(logs: { "1" => ["", " \n", "boom"] }))
    assert_equal "boom", failed_logs(env, "o/r", "1")
    env, io = fake_env(FakeGh.new(logs: { "1" => [""] }))
    assert_equal "", failed_logs(env, "o/r", "1")
    assert_equal LOG_FETCH_RETRIES, io.string.scan(/failed logs empty/).size
  end

  # --- watch ---

  test "watch: passes straight away" do
    gh = FakeGh.new(states: { "1" => [PASSED] })
    env, io = fake_env(gh)
    assert watch(env, [:run, "o/r", "1"])
    assert_empty gh.writes
    assert_match %r{\Ahttps://github.com/o/r/actions/runs/1\n}, io.string
  end

  test "watch: waits out a running run" do
    gh = FakeGh.new(states: { "1" => [RUNNING, RUNNING, RUNNING, PASSED] })
    env, io = fake_env(gh, poll: 7)
    assert watch(env, [:run, "o/r", "1"])
    assert_equal 21, env.clock.slept
    assert_equal 1, io.string.scan(/rechecking every 7s/).size
  end

  test "watch: one rerun, despite the stale completed state" do
    gh = FakeGh.new(states: { "1" => [FAILED, FAILED, RUNNING, PASSED] })
    env, = fake_env(gh, delay: 30)
    assert watch(env, [:run, "o/r", "1"])
    assert_equal [[:rerun, "1"]], gh.writes
    assert_equal 31, env.clock.slept
  end

  test "watch: gives up once retries run out" do
    gh = FakeGh.new(states: { "1" => [FAILED, RUNNING, FAILED] })
    env, io = fake_env(gh, retries: 1)
    refute watch(env, [:run, "o/r", "1"])
    assert_equal [[:rerun, "1"]], gh.writes
    assert_match(/rerunning failed jobs \(attempt 1\/1\)/, io.string)
    assert_match(/retries exhausted \(1\) -- giving up/, io.string)
  end

  test "watch: completed without failed jobs gives up" do
    env, io = fake_env(FakeGh.new(states: { "1" => [run_data("completed", "cancelled")] }))
    refute watch(env, [:run, "o/r", "1"])
    assert_match(/finished: cancelled -- nothing failed to rerun/, io.string)
  end

  test "watch: rerun pattern matched" do
    gh = FakeGh.new(states: { "1" => [FAILED, RUNNING, PASSED] }, logs: { "1" => ["Cannot talk to archive"] })
    env, io = fake_env(gh, patterns: ["cannot talk"], ignore_case: true)
    assert watch(env, [:run, "o/r", "1"])
    assert_equal [[:rerun, "1"]], gh.writes
    assert_match(/matched pattern: "cannot talk"/, io.string)
  end

  test "watch: stop-on pattern gives up without rerunning" do
    gh = FakeGh.new(states: { "1" => [FAILED] }, logs: { "1" => ["flaky\nfatal"] })
    env, io = fake_env(gh, patterns: ["flaky"], stop_patterns: ["fatal"])
    refute watch(env, [:run, "o/r", "1"])
    assert_empty gh.writes
    assert_match(/stop-on pattern matched: "fatal"/, io.string)
  end

  test "watch: no retry pattern matched" do
    gh = FakeGh.new(states: { "1" => [FAILED] }, logs: { "1" => ["boom"] })
    env, io = fake_env(gh, patterns: ["flaky"])
    refute watch(env, [:run, "o/r", "1"])
    assert_empty gh.writes
    assert_match(/no retry pattern matched/, io.string)
  end

  test "watch: unreadable logs count as transient" do
    gh = FakeGh.new(states: { "1" => [FAILED, RUNNING, PASSED] }, logs: { "1" => [""] })
    env, io = fake_env(gh, patterns: ["flaky"])
    assert watch(env, [:run, "o/r", "1"])
    assert_equal [[:rerun, "1"]], gh.writes
    assert_match(/assuming transient and rerunning/, io.string)
  end

  test "watch: dry run never writes" do
    gh = FakeGh.new(states: { "1" => [FAILED], "2" => [STALLED] })
    env, io = fake_env(gh, dry_run: true, cancel: true)
    assert watch(env, [:run, "o/r", "1"])
    assert watch(env, [:run, "o/r", "2"])
    assert_empty gh.writes
    assert_match(/\[dry-run\] would rerun failed jobs for run 1/, io.string)
    assert_match(/\[dry-run\] would cancel run 2/, io.string)
  end

  test "watch: cancels a stalled run, then reruns" do
    gh = FakeGh.new(states: { "1" => [STALLED, FAILED, RUNNING, PASSED] })
    env, = fake_env(gh, cancel: true)
    assert watch(env, [:run, "o/r", "1"])
    assert_equal [[:cancel, "1"], [:rerun, "1"]], gh.writes
  end

  test "watch: overall timeout while a job wedges" do
    env, io = fake_env(FakeGh.new(states: { "1" => [RUNNING] }), timeout: 30, poll: 10)
    refute watch(env, [:run, "o/r", "1"])
    assert_equal 30, env.clock.slept
    assert_match(/overall timeout \(30s\) exceeded/, io.string)
  end

  test "watch: failed rerun gives up" do
    gh = FakeGh.new(states: { "1" => [FAILED] }, rerun_ok: false)
    env, io = fake_env(gh)
    refute watch(env, [:run, "o/r", "1"])
    assert_match(/gh run rerun failed -- giving up/, io.string)
  end

  test "watch: pr resolves to its failed run" do
    rollup = [rollup_check("a", 5, "FAILURE", "2026-01-01"), rollup_check("b", 6, "SUCCESS", "2026-01-02")]
    gh = FakeGh.new(rollups: { "7" => [rollup] }, states: { "5" => [PASSED] })
    env, io = fake_env(gh)
    assert watch(env, [:pr, "o/r", "7"])
    assert_match(%r{resolved o/r#7 -> run 5\n}, io.string)
    assert_match(%r{https://github.com/o/r/actions/runs/5\n}, io.string)
  end

  test "watch: failed pr lookup gives up" do
    env, io = fake_env(FakeGh.new(rollups: { "7" => [GhError.new("not found")] }))
    refute watch(env, [:pr, "o/r", "7"])
    assert_match(%r{failed to look up o/r#7:\nnot found}, io.string)
  end

  test "watch_all: labels each target, reports the lot" do
    gh = FakeGh.new(states: { "1" => [PASSED], "2" => [run_data("completed", "cancelled")] },
                    rollups: { "9" => [[rollup_check("x", 2, "CANCELLED", "2026-01-01")]] })
    env, io = fake_env(gh)
    refute watch_all(env, [[:run, "o/r", "1"], [:pr, "o/r", "9"]])
    assert_match(/^\[gh-retry 1\] run 1 passed$/, io.string)
    assert_match(/^\[gh-retry #9\] run 2 finished: cancelled/, io.string)
    assert_match(%r{^\[gh-retry\] o/r/1 ok$}, io.string)
    assert_match(%r{^\[gh-retry\] o/r#9 gave up$}, io.string)
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
