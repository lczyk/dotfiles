#!/usr/bin/env ruby
# re-grant screen recording for alacritty after an upgrade.
#
# alacritty is ad-hoc signed, so tcc pins the screen recording grant to the
# exact binary hash. every upgrade invalidates it silently: the toggle in
# system settings still shows on, but `screencapture` fails with "could not
# create image from display". run this from inside alacritty to fix it.

BUNDLE_ID = ARGV.fetch(0, "org.alacritty")
TEST_SHOT = "/tmp/regrant-test.png"

def run(*cmd)
  puts "+ #{cmd.join(' ')}"
  system(*cmd)
end

unless run("tccutil", "reset", "ScreenCapture", BUNDLE_ID)
  abort "tccutil reset failed"
end

# a capture attempt with no grant fires the system permission prompt for the
# responsible app (the terminal this runs in).
puts "triggering the permission prompt -- click allow when it appears"
run("screencapture", "-x", TEST_SHOT)
File.delete(TEST_SHOT) if File.exist?(TEST_SHOT)

puts <<~MSG

  done. now quit and relaunch the terminal (the grant only applies to a
  fresh process), then verify with:

      screencapture -x /tmp/t.png && ls -la /tmp/t.png
MSG
