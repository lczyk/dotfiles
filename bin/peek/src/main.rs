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

use std::io::{self, Read};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    parse_args(&args);

    let mut buffer = String::new();
    io::stdin().read_to_string(&mut buffer).expect("Failed to read from stdin");

    print!("{}", buffer);
    eprint!("{}", buffer);    
}
