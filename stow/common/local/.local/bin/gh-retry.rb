#!/usr/bin/env ruby
# frozen_string_literal: true

# gh-retry -- rerun a failed gh actions run, optionally gated on log patterns.
#
# watches a run; when it fails, reruns just the failed jobs. if patterns are
# given, only reruns when one of them appears in the failed-job logs (i.e. the
# failure looks transient). loops up to N times with a delay between attempts.
#
# shells out to the user's `gh`.

require "optparse"
require "json"
require "open3"

# clean ctrl+c: don't dump the open3 reader-thread backtrace.
Thread.report_on_exception = false

# --- config / defaults ------------------------------------------------------

retries = 3
delay = 30
poll = 10
timeout = 0 # 0 = no overall deadline
stop_patterns = []
ignore_case = false
cancel = false
dry_run = false

parser = OptionParser.new do |o|
  o.banner = <<~USAGE
    usage: gh-retry [options] <target> [pattern...]

    watch a gh actions run; on failure, rerun the failed jobs. if patterns are
    given, only rerun when one appears in the failed logs. always reruns failed
    jobs only (never the whole run).

    <target> identifies the run (need not live in the current repo), either as
      OWNER/REPO/RUN_ID          e.g. canonical/chisel-releases/29429492601
    or a github url (anything with .../actions/runs/RUN_ID in it), e.g.
      https://github.com/canonical/chisel-releases/actions/runs/29429492601/job/8756?pr=1046
    or a pull request (latest failed actions run on that PR; else the latest run):
      https://github.com/canonical/sd-tools/pull/4261
      canonical/sd-tools#4261

    examples:
      gh-retry canonical/chisel-releases/29429492601
      gh-retry canonical/chisel-releases/29429492601 \\
               "context deadline exceeded (Client.Timeout exceeded while awaiting headers)" \\
               "error: cannot talk to archive:"

    options:
  USAGE

  o.on("-N", "--retries N", Integer, "max reruns after first failure (default #{retries}); -9 is short for -N 9") { |v| retries = v }
  o.on("-d", "--delay SECONDS", Integer, "delay between reruns (default #{delay})") { |v| delay = v }
  o.on("-p", "--poll SECONDS", Integer, "status poll interval while watching (default #{poll})") { |v| poll = v }
  o.on("-t", "--timeout SECONDS", Integer, "overall wall-clock deadline; abort if exceeded, e.g. when a job wedges in_progress (default: none)") { |v| timeout = v }
  o.on("-s", "--stop-on PATTERN", "give up immediately if PATTERN appears in the failed logs, even if a retry pattern also matches (repeatable)") { |v| stop_patterns << v }
  o.on("-i", "--ignore-case", "case-insensitive pattern matching") { ignore_case = true }
  o.on("-c", "--cancel", "if nothing is running but queued jobs keep the run open, cancel it to force a rerun (gh can't rerun an in-progress run)") { cancel = true }
  o.on("-n", "--dry-run", "watch and report what would happen, but stop before the first write action (rerun/cancel)") { dry_run = true }
  o.on("-h", "--help", "show this help") do
    puts o
    exit 0
  end
end

# -9 means -N 9 (same idea as nice/kill numeric shorts).
ARGV.replace(ARGV.flat_map { |arg| arg =~ /\A-(\d+)\z/ ? ["-N", $1] : [arg] })
parser.parse!(ARGV)

if ARGV.empty?
  warn parser
  exit 2
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

target = ARGV.shift
parsed = parse_target(target)
if parsed.nil?
  warn "gh-retry: could not parse target #{target.inspect} -- expected OWNER/REPO/RUN_ID, a github run url, or a pull request"
  exit 2
end

patterns = ARGV.dup

# --- colours ----------------------------------------------------------------

USE_COLOR = $stdout.tty? && !ENV.key?("NO_COLOR")

# basic 8-color SGR only (30-37). bold black is the usual terminal gray;
# no 256-color (38;5;N) and no aixterm brights (90-97).
def colorize(code, str, bold: false)
  attr = bold ? "1;#{code}" : code
  USE_COLOR ? "\e[#{attr}m#{str}\e[0m" : str
end

def info(msg)  warn(colorize("34", "[gh-retry] ") + msg) end  # blue
def good(msg)  warn(colorize("32", "[gh-retry] ") + msg) end  # green
def warn_(msg) warn(colorize("33", "[gh-retry] ") + msg) end  # yellow
def bad(msg)   warn(colorize("31", "[gh-retry] ") + msg) end  # red

def color_status(status)
  code = case status
         when "success", "neutral" then "32"
         when "failure", "cancelled", "timed_out", "startup_failure", "action_required" then "31"
         when "in_progress", "queued", "pending", "waiting" then "33"
         when "skipped" then "30"
         end
  # bold so black reads as gray; prefix stays unbolded.
  code ? colorize(code, status, bold: true) : status
end

Signal.trap("INT") do
  warn
  warn_ "interrupted"
  exit 130
end

# --- gh helpers -------------------------------------------------------------

def gh_capture(repo, *args)
  out, status = Open3.capture2e("gh", *args, "--repo", repo)
  [out, status.success?]
end

# a pull request is not a run. pick one actions run from its checks: a failed
# one if any (latest by completed/started time), otherwise the latest run so
# the watcher can wait or report success. multiple failed runs: warn, take latest.
def resolve_pr_run(repo, number)
  out, ok = gh_capture(repo, "pr", "view", number, "--json", "statusCheckRollup")
  unless ok
    bad "failed to look up #{repo}##{number}:\n#{out}"
    exit 1
  end

  rollup = JSON.parse(out)["statusCheckRollup"] || []
  runs = {}
  rollup.each do |check|
    url = check["detailsUrl"] || check["targetUrl"] || ""
    next unless url =~ %r{/actions/runs/(\d+)}

    id = $1
    stamp = check["completedAt"] || check["startedAt"] || ""
    entry = runs[id] ||= { "id" => id, "stamp" => stamp, "failed" => false, "checks" => [] }
    entry["stamp"] = stamp if stamp > entry["stamp"]
    conclusion = check["conclusion"].to_s.downcase
    status = conclusion.empty? ? check["status"].to_s.downcase : conclusion
    status = "unknown" if status.empty?
    entry["checks"] << [check["name"], status] if check["name"]
    entry["failed"] = true if %w[failure cancelled timed_out].include?(conclusion)
  end

  if runs.empty?
    bad "no actions runs found on #{repo}##{number}"
    exit 1
  end

  failed = runs.values.select { |r| r["failed"] }
  chosen = (failed.empty? ? runs.values : failed).max_by { |r| r["stamp"] }
  others = failed.map { |r| r["id"] } - [chosen["id"]]
  unless others.empty?
    warn_ "#{repo}##{number} has other failed runs (#{others.join(", ")}); watching #{chosen["id"]}"
  end
  info "resolved #{repo}##{number} -> run #{chosen["id"]}"
  chosen["checks"].uniq.each { |name, status| info "  #{name}  #{color_status(status)}" }
  chosen["id"]
end

def gh_stream(repo, *args)
  system("gh", *args, "--repo", repo)
end

# querying the run can itself hit a transient gh/network/api failure. since the
# whole point of this tool is riding out flaky infra, don't let a single bad
# poll abort the watch -- retry a few times before giving up.
POLL_QUERY_RETRIES = 5
POLL_QUERY_BACKOFF = 5 # seconds between failed-poll retries

def state_for(repo, run_id)
  attempts = 0
  loop do
    out, ok = gh_capture(repo, "run", "view", run_id, "--json", "status,conclusion,jobs")
    if ok
      begin
        return JSON.parse(out)
      rescue JSON::ParserError => e
        # gh returned success but unparsable output -- treat like a transient hiccup.
        out = "#{e.message}\n#{out}"
        ok = false
      end
    end

    attempts += 1
    if attempts > POLL_QUERY_RETRIES
      bad "failed to query run #{run_id} after #{POLL_QUERY_RETRIES} retries:\n#{out}"
      exit 1
    end
    warn_ "poll failed (attempt #{attempts}/#{POLL_QUERY_RETRIES}), retrying in #{POLL_QUERY_BACKOFF}s"
    sleep POLL_QUERY_BACKOFF
  end
end

# poll until the run is actionable. returns:
#   "success"  -- run completed, all green
#   :retry     -- run completed with failures; safe to rerun --failed now
#   :cancel    -- (cancel mode only) nothing running + failures, but queued jobs
#                 keep the run in_progress; caller must cancel to force a rerun
#   :timeout   -- the overall deadline passed while still waiting (e.g. a job
#                 wedged in_progress and never returned)
#   <other>    -- run completed, not green, nothing failed to rerun (give up)
# keeps polling while any job is still in_progress. note: gh refuses to rerun a
# run that isn't `completed`, so by default we wait for completion. deadline is a
# Time or nil (no deadline).
def wait_for_actionable(repo, run_id, poll, cancel, deadline)
  last = nil
  loop do
    data = state_for(repo, run_id)
    jobs = data["jobs"] || []
    running = jobs.count { |j| j["status"] == "in_progress" }
    failed  = jobs.count { |j| j["status"] == "completed" && j["conclusion"] == "failure" }

    if data["status"] == "completed"
      return "success" if data["conclusion"] == "success"
      return :retry if failed.positive?

      return data["conclusion"] || "unknown"
    end

    # run still in_progress. in cancel mode, if nothing is actually running and
    # something has failed, the queued jobs are just blocked -- cancel to move on.
    return :cancel if cancel && running.zero? && failed.positive?

    # bail if we've blown the overall wall-clock deadline while still waiting --
    # catches a job that wedges in_progress and never completes.
    return :timeout if deadline && Time.now >= deadline

    label = "#{data['status']} (#{running} running, #{failed} failed)"
    if label != last
      info "status: #{label}"
      info "rechecking every #{poll}s ..."
      last = label
    end
    sleep poll
  end
end

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

def wait_until_restarted(repo, run_id, poll)
  RESTART_POLLS.times do
    return true if state_for(repo, run_id)["status"] != "completed"

    sleep poll
  end
  warn_ "run #{run_id} still reports completed after rerun -- proceeding anyway"
  false
end

def failed_logs(repo, run_id)
  attempts = 0
  loop do
    out, _ok = gh_capture(repo, "run", "view", run_id, "--log-failed")
    return out unless out.strip.empty?

    attempts += 1
    return out if attempts > LOG_FETCH_RETRIES

    warn_ "failed logs empty (attempt #{attempts}/#{LOG_FETCH_RETRIES}), retrying in #{LOG_FETCH_BACKOFF}s"
    sleep LOG_FETCH_BACKOFF
  end
end

def match_pattern(logs, patterns, ignore_case)
  hay = ignore_case ? logs.downcase : logs
  patterns.find do |p|
    needle = ignore_case ? p.downcase : p
    hay.include?(needle)
  end
end

# --- resolve target ---------------------------------------------------------

kind, repo, ident = parsed
run_id = kind == :pr ? resolve_pr_run(repo, ident) : ident

# first line: the resolved run url, plain and copy-pasteable.
warn "https://github.com/#{repo}/actions/runs/#{run_id}"

# --- main loop --------------------------------------------------------------

attempts_left = retries
deadline = timeout.positive? ? Time.now + timeout : nil

loop do
  info "watching run #{run_id} in #{repo} ..."
  state = wait_for_actionable(repo, run_id, poll, cancel, deadline)

  if state == :timeout
    bad "overall timeout (#{timeout}s) exceeded while waiting on run #{run_id} -- giving up"
    exit 1
  elsif state == "success"
    good "run #{run_id} passed"
    exit 0
  elsif state == :cancel
    if dry_run
      good "[dry-run] would cancel run #{run_id} (failures + queued, nothing running), then rerun failed jobs"
      exit 0
    end
    warn_ "run #{run_id} stalled (failures + queued, nothing running) -- cancelling to force rerun"
    gh_stream(repo, "run", "cancel", run_id)
    sleep poll # let the cancellation propagate before we re-poll
    # loop back; once the run reports completed we can rerun.
    next
  elsif state != :retry
    bad "run #{run_id} finished: #{state} -- nothing failed to rerun, giving up"
    exit 1
  end

  warn_ "run #{run_id} completed with failures"

  unless patterns.empty? && stop_patterns.empty?
    logs = failed_logs(repo, run_id)
    if logs.strip.empty?
      # logs never materialised -- we can't classify the failure. don't treat
      # "couldn't read the logs" as "not transient"; assume transient and rerun.
      warn_ "failed logs empty/unavailable -- can't classify, assuming transient and rerunning"
    else
      # deny-list wins: a stop-on match means a real failure, give up now even
      # if a retry pattern also matches somewhere in the noisy log.
      aborted = match_pattern(logs, stop_patterns, ignore_case)
      unless aborted.nil?
        bad "stop-on pattern matched: #{aborted.inspect} -- treating as a real failure, giving up"
        exit 1
      end

      unless patterns.empty?
        matched = match_pattern(logs, patterns, ignore_case)
        if matched.nil?
          bad "no retry pattern matched failed logs -- not transient, giving up"
          exit 1
        end
        info "matched pattern: #{matched.inspect}"
      end
    end
  end

  if dry_run
    good "[dry-run] would rerun failed jobs for run #{run_id} (gh run rerun #{run_id} --failed)"
    exit 0
  end

  if attempts_left <= 0
    bad "retries exhausted (#{retries}) -- giving up"
    exit 1
  end

  attempts_left -= 1
  attempt = retries - attempts_left
  warn_ "rerunning failed jobs (attempt #{attempt}/#{retries})"

  unless gh_stream(repo, "run", "rerun", run_id, "--failed")
    bad "gh run rerun failed -- giving up"
    exit 1
  end

  sleep delay if delay.positive?
  # don't let the next watch iteration read the pre-rerun completed state.
  wait_until_restarted(repo, run_id, poll)
end
