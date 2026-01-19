// peek is a

const VERSION: &str = env!("CARGO_PKG_VERSION");
const GIT_SHA: &str = env!("PEEK_GIT_SHA");
const GIT_STATUS: &str = env!("PEEK_GIT_STATUS");
const BUILD_DATE: &str = env!("PEEK_BUILD_DATE");
const HELP: &str = r#"Usage: peek [OPTIONS]
Take all the input from stdin, print it to stderr and stdout.
Equivalent to `tee /dev/stderr`.

Options:
  -h, --help        Print help information
  -v, --version     Print version information
  --no-line-buffer  Disable line buffering
"#;

const BUFFER_SIZE: usize = 8192;


fn parse_args(args: &[String]) -> bool {
    let mut line_buffered = true;
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "-v" | "--version" => {
                println!("peek {}+{} ({}, {})", VERSION, GIT_SHA, BUILD_DATE, GIT_STATUS);
                std::process::exit(0);
            }
            "-h" | "--help" => {
                println!("{}", HELP);
                std::process::exit(0);
            }
            "--no-line-buffer" => {
                line_buffered = false;
            }
            _ => {
                println!("{}", HELP);
                std::process::exit(1);
            }
        }
    }
    line_buffered
}

use std::io::{self, BufRead, Read, Write};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let line_buffered = parse_args(&args);

    let stdin = io::stdin();
    let mut stdin = stdin.lock();
    let stdout = io::stdout();
    let mut stdout = stdout.lock();
    let stderr = io::stderr();
    let mut stderr = stderr.lock();

    if line_buffered {
        let mut buffer = Vec::with_capacity(BUFFER_SIZE);
        loop {
            buffer.clear();
            let read = stdin
                .read_until(b'\n', &mut buffer)
                .expect("Failed to read from stdin");
            if read == 0 {
                break;
            }

            if let Err(err) = stdout.write_all(&buffer) {
                if err.kind() == io::ErrorKind::BrokenPipe {
                    return;
                }
                panic!("Failed to write to stdout: {err}");
            }

            if let Err(err) = stderr.write_all(&buffer) {
                if err.kind() == io::ErrorKind::BrokenPipe {
                    return;
                }
                panic!("Failed to write to stderr: {err}");
            }
        }
    } else {
        let mut buffer = vec![0u8; BUFFER_SIZE];
        loop {
            let read = stdin.read(&mut buffer).expect("Failed to read from stdin");
            if read == 0 {
                break;
            }

            if let Err(err) = stdout.write_all(&buffer[..read]) {
                if err.kind() == io::ErrorKind::BrokenPipe {
                    return;
                }
                panic!("Failed to write to stdout: {err}");
            }

            if let Err(err) = stderr.write_all(&buffer[..read]) {
                if err.kind() == io::ErrorKind::BrokenPipe {
                    return;
                }
                panic!("Failed to write to stderr: {err}");
            }
        }
    }
}
