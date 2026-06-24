#!/usr/bin/env node
// shared symlink-safe flag io for the caveman / ponytail mode flags.
//
// the flag path is predictable (~/.claude/.{caveman,ponytail}-active), so a
// local attacker could pre-create it as a symlink to clobber another file.
// writes go through a temp + atomic rename with O_NOFOLLOW and 0600; reads
// refuse symlinks and cap the size. callers validate the contents themselves.

const fs = require('fs');
const path = require('path');
const os = require('os');

const MAX_FLAG_BYTES = 64;
const O_NOFOLLOW = typeof fs.constants.O_NOFOLLOW === 'number' ? fs.constants.O_NOFOLLOW : 0;

// resolve the real dir behind flagPath, refusing symlinked dirs that escape the
// current user / home. returns the safe dir, or null if it can't be trusted.
function resolveFlagDir(flagPath) {
  const flagDir = path.dirname(flagPath);
  fs.mkdirSync(flagDir, { recursive: true });
  const lstat = fs.lstatSync(flagDir);
  if (!lstat.isSymbolicLink()) return flagDir;

  const realDir = fs.realpathSync(flagDir);
  const realStat = fs.statSync(realDir);
  if (!realStat.isDirectory()) return null;
  if (typeof process.getuid === 'function') {
    return realStat.uid === process.getuid() ? realDir : null;
  }
  // windows: no uid -- require the target stay within home
  const real = path.resolve(realDir).toLowerCase();
  const home = path.resolve(os.homedir()).toLowerCase();
  return (real === home || real.startsWith(home + path.sep)) ? realDir : null;
}

function safeWriteFlag(flagPath, content) {
  try {
    const realDir = resolveFlagDir(flagPath);
    if (!realDir) return;

    const realPath = path.join(realDir, path.basename(flagPath));
    try {
      if (fs.lstatSync(realPath).isSymbolicLink()) return;
    } catch (e) {
      if (e.code !== 'ENOENT') return;
    }

    const tempPath = path.join(realDir, '.' + path.basename(flagPath) + '.' + process.pid);
    const flags = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | O_NOFOLLOW;
    let fd;
    try {
      fd = fs.openSync(tempPath, flags, 0o600);
      fs.writeSync(fd, String(content));
      try { fs.fchmodSync(fd, 0o600); } catch (e) { /* best-effort on windows */ }
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
    fs.renameSync(tempPath, realPath);
  } catch (e) {
    // silent fail -- flag is best-effort
  }
}

// read the flag, refusing symlinks and oversized files. returns the trimmed
// raw string (caller lowercases / validates), or null.
function readFlagRaw(flagPath) {
  try {
    let st;
    try {
      st = fs.lstatSync(flagPath);
    } catch (e) {
      return null;
    }
    if (st.isSymbolicLink() || !st.isFile() || st.size > MAX_FLAG_BYTES) return null;

    let fd;
    let out;
    try {
      fd = fs.openSync(flagPath, fs.constants.O_RDONLY | O_NOFOLLOW);
      const buf = Buffer.alloc(MAX_FLAG_BYTES);
      const n = fs.readSync(fd, buf, 0, MAX_FLAG_BYTES, 0);
      out = buf.slice(0, n).toString('utf8');
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
    }
    return out.trim();
  } catch (e) {
    return null;
  }
}

module.exports = { safeWriteFlag, readFlagRaw, MAX_FLAG_BYTES };
