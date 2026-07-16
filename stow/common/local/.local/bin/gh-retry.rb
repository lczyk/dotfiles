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
Signal.trap("INT") do
  warn "\ngh-retry: interrupted"
  exit 130
end

# --- config / defaults ------------------------------------------------------

retries = 3
delay = 30
poll = 10
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

    examples:
      gh-retry canonical/chisel-releases/29429492601
      gh-retry canonical/chisel-releases/29429492601 \\
               "context deadline exceeded (Client.Timeout exceeded while awaiting headers)" \\
               "error: cannot talk to archive:"

    options:
  USAGE

  o.on("-n", "--retries N", Integer, "max reruns after first failure (default #{retries})") { |v| retries = v }
  o.on("-d", "--delay SECONDS", Integer, "delay between reruns (default #{delay})") { |v| delay = v }
  o.on("-p", "--poll SECONDS", Integer, "status poll interval while watching (default #{poll})") { |v| poll = v }
  o.on("-i", "--ignore-case", "case-insensitive pattern matching") { ignore_case = true }
  o.on("-c", "--cancel", "if nothing is running but queued jobs keep the run open, cancel it to force a rerun (gh can't rerun an in-progress run)") { cancel = true }
  o.on("--dry-run", "watch and report what would happen, but stop before the first write action (rerun/cancel)") { dry_run = true }
  o.on("-h", "--help", "show this help") do
    puts o
    exit 0
  end
end

parser.parse!(ARGV)

if ARGV.empty?
  warn parser
  exit 2
end

# parse a target into [repo, run_id]. accepts either OWNER/REPO/RUN_ID or a
# github url containing .../actions/runs/RUN_ID.
def parse_target(target)
  if target =~ %r{github\.com/([^/]+)/([^/]+)/actions/runs/(\d+)}
    ["#{$1}/#{$2}", $3]
  elsif target =~ %r{\A([^/\s]+)/([^/\s]+)/(\d+)\z}
    ["#{$1}/#{$2}", $3]
  end
end

target = ARGV.shift
repo, run_id = parse_target(target)
if repo.nil?
  warn "gh-retry: could not parse target #{target.inspect} -- expected OWNER/REPO/RUN_ID or a github run url"
  exit 2
end

patterns = ARGV.dup

# --- colours ----------------------------------------------------------------

USE_COLOR = $stdout.tty? && !ENV.key?("NO_COLOR")

def colorize(code, str)
  USE_COLOR ? "\e[#{code}m#{str}\e[0m" : str
end

def info(msg)  warn(colorize("34", "[gh-retry] ") + msg) end  # blue
def good(msg)  warn(colorize("32", "[gh-retry] ") + msg) end  # green
def warn_(msg) warn(colorize("33", "[gh-retry] ") + msg) end  # yellow
def bad(msg)   warn(colorize("31", "[gh-retry] ") + msg) end  # red

# --- gh helpers -------------------------------------------------------------

def gh_capture(repo, *args)
  out, status = Open3.capture2e("gh", *args, "--repo", repo)
  [out, status.success?]
end

def gh_stream(repo, *args)
  system("gh", *args, "--repo", repo)
end

def state_for(repo, run_id)
  out, ok = gh_capture(repo, "run", "view", run_id, "--json", "status,conclusion,jobs")
  unless ok
    bad "failed to query run #{run_id}:\n#{out}"
    exit 1
  end
  JSON.parse(out)
end

# poll until the run is actionable. returns:
#   "success"  -- run completed, all green
#   :retry     -- run completed with failures; safe to rerun --failed now
#   :cancel    -- (cancel mode only) nothing running + failures, but queued jobs
#                 keep the run in_progress; caller must cancel to force a rerun
#   <other>    -- run completed, not green, nothing failed to rerun (give up)
# keeps polling while any job is still in_progress. note: gh refuses to rerun a
# run that isn't `completed`, so by default we wait for completion.
def wait_for_actionable(repo, run_id, poll, cancel)
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

    label = "#{data['status']} (#{running} running, #{failed} failed)"
    info "status: #{label}" if label != last
    last = label
    sleep poll
  end
end

def failed_logs(repo, run_id)
  out, _ok = gh_capture(repo, "run", "view", run_id, "--log-failed")
  out
end

def match_pattern(logs, patterns, ignore_case)
  hay = ignore_case ? logs.downcase : logs
  patterns.find do |p|
    needle = ignore_case ? p.downcase : p
    hay.include?(needle)
  end
end

# --- main loop --------------------------------------------------------------

attempts_left = retries

loop do
  info "watching run #{run_id} in #{repo} ..."
  state = wait_for_actionable(repo, run_id, poll, cancel)

  if state == "success"
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

  unless patterns.empty?
    logs = failed_logs(repo, run_id)
    matched = match_pattern(logs, patterns, ignore_case)
    if matched.nil?
      bad "no retry pattern matched failed logs -- not transient, giving up"
      exit 1
    end
    info "matched pattern: #{matched.inspect}"
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
end
