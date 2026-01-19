// peek is a

const VERSION: &str = env!("CARGO_PKG_VERSION");
const HELP: &str = r#"Usage: peek [OPTIONS]
Take all the input from stdin, print it to stderr and stdout.
Equivalent to `tee /dev/stderr`.

Options:
  -h, --help     Print help information
  -v, --version  Print version information
"#;


fn parse_args(args: &[String]) -> () {
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "-v" | "--version" => {
                println!("peek {}", VERSION);
                std::process::exit(0);
            }
            "-h" | "--help" => {
                println!("{}", HELP);
                std::process::exit(0);
            }
            _ => {
                println!("{}", HELP);
                std::process::exit(1);
            }
        }
    }
}

use std::io::{self, BufRead, Write};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    parse_args(&args);

    let stdin = io::stdin();
    let mut stdin = stdin.lock();
    let stdout = io::stdout();
    let mut stdout = stdout.lock();
    let stderr = io::stderr();
    let mut stderr = stderr.lock();

    let mut buffer = Vec::with_capacity(8192);
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
}
