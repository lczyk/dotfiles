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
# with side effects (gh, time, output) comes in through an Env.

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

main(ARGV)
