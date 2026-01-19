use std::process::Command;

fn command_output(command: &mut Command) -> Option<String> {
    let output = command.output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Some(text)
}

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".into());

    let mut git_sha_cmd = Command::new("git");
    git_sha_cmd
        .current_dir(&manifest_dir)
        .args(["rev-parse", "--short", "HEAD"]);
    let git_sha = command_output(&mut git_sha_cmd)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());

    let mut git_status_cmd = Command::new("git");
    git_status_cmd
        .current_dir(&manifest_dir)
        .args(["status", "--porcelain", "--", "."]);
    let git_status = command_output(&mut git_status_cmd)
        .map(|s| if s.is_empty() { "clean".to_string() } else { "dirty".to_string() })
        .unwrap_or_else(|| "unknown".to_string());

    let mut build_date_cmd = Command::new("date");
    build_date_cmd.args(["-u", "+%Y-%m-%dT%H:%M:%SZ"]);
    let build_date = command_output(&mut build_date_cmd)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=TIME_FUZZER_GIT_SHA={}", git_sha);
    println!("cargo:rustc-env=TIME_FUZZER_GIT_STATUS={}", git_status);
    println!("cargo:rustc-env=TIME_FUZZER_BUILD_DATE={}", build_date);

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=.git/HEAD");
    println!("cargo:rerun-if-changed=.git/index");
}
