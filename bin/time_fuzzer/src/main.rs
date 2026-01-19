use std::io::{self, Read};

const VERSION: &str = env!("CARGO_PKG_VERSION");
const GIT_SHA: &str = env!("TIME_FUZZER_GIT_SHA");
const GIT_STATUS: &str = env!("TIME_FUZZER_GIT_STATUS");
const BUILD_DATE: &str = env!("TIME_FUZZER_BUILD_DATE");
const HELP: &str = r#"Usage: time_fuzzer [OPTIONS] <TIME>
Convert a specific time into a fuzzy, human-readable format.
Options:
  -h, --help     Print help information
  -v, --version  Print version information
  -j, --just     Use "just after" and "just before" for times within 2 minutes
                 of the hour instead of "o'clock" and "five past/to".
Arguments:
    <TIME>         The time to be converted into fuzzy format in HH:MM format
                   For example, "14:30" for 2:30 PM. This is expected to be an
                   output from the `date +%H:%M` command.
Alternatively the time can be piped into the program via standard input.
"#;

struct Args {
    just: bool,
    input: Option<String>,
}

fn parse_args(args: &[String]) -> Args {
    let mut just = false;
    let mut input: Option<String> = None;

    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "-h" | "--help" => {
                println!("{}", HELP);
                std::process::exit(0);
            }
            "-v" | "--version" => {
                println!("time_fuzzer {}+{} ({}, {})", VERSION, GIT_SHA, BUILD_DATE, GIT_STATUS);
                std::process::exit(0);
            }
            "-j" | "--just" => {
                just = true;
            }
            _ => {
                input = Some(arg.clone());
            }
        }
    }

    Args { just, input }
}

fn main() {

    let _args: Vec<String> = std::env::args().collect();
    
    let args = parse_args(&_args);

    let input_time = match args.input {
        Some(t) => t,
        None => {
            let mut buffer = String::new();
            io::stdin().read_to_string(&mut buffer).expect("Failed to read from stdin");
            buffer.trim().to_string()
        }
    };

    let (hour, minute) = match parse_input_time(&input_time) {
        Ok((h, m)) => (h, m),
        Err(e) => {
            eprintln!("Error parsing time: {}", e);
            return;
        }
    };

    let fuzzy_time = match convert_to_fuzzy_time(hour, minute, args.just) {
        Ok(ft) => ft,
        Err(e) => {
            eprintln!("Error converting to fuzzy time: {}", e);
            return;
        }
    };

    println!("{}", fuzzy_time);
}

fn parse_input_time(input: &str) -> Result<(u32, u32), String> {
    let parts: Vec<&str> = input.split(':').collect();
    if parts.len() != 2 {
        return Err("Input time must be in HH:MM format".to_string());
    }
    let hour: u32 = parts[0].parse().map_err(|_| "Invalid hour".to_string())?;
    let minute: u32 = parts[1].parse().map_err(|_| "Invalid minute".to_string())?;
    if hour > 23 || minute > 59 {
        return Err("Hour must be between 0-23 and minute between 0-59".to_string());
    }
    Ok((hour, minute))
}

fn convert_to_fuzzy_time(hour: u32, minute: u32, just: bool) -> Result<String, String> {
    let hours = [
        "twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven",
    ];

    let current_hour_24 = hour;
    let next_hour_24 = (hour + 1) % 24;

    let hour_label = |hour_24: u32| -> &str {
        if hour_24 == 0 {
            "midnight"
        } else {
            hours[(hour_24 % 12) as usize]
        }
    };

    if minute == 0 && current_hour_24 == 0 {
        return Ok("midnight".to_string());
    }

    if just {
        if minute == 1 {
            return Ok(format!("just after {}", hour_label(current_hour_24)));
        } else if minute == 59 {
            return Ok(format!("just before {}", hour_label(next_hour_24)));
        }
    }

    let result: Option<String> = match minute {
        0 => Some(format!("{} o'clock", hour_label(current_hour_24))),
        1..=2 | 58..=59 => {
            if minute <= 2 {
                Some(format!("five past {}", hour_label(current_hour_24)))
            } else {
                Some(format!("five to {}", hour_label(next_hour_24)))
            }
        }
        3..=7 => Some(format!("five past {}", hour_label(current_hour_24))),
        8..=12 => Some(format!("ten past {}", hour_label(current_hour_24))),
        13..=17 => Some(format!("quarter past {}", hour_label(current_hour_24))),
        18..=22 => Some(format!("twenty past {}", hour_label(current_hour_24))),
        23..=27 => Some(format!("twenty-five past {}", hour_label(current_hour_24))),
        28..=32 => Some(format!("half past {}", hour_label(current_hour_24))),
        33..=37 => {
            Some(format!("twenty-five to {}", hour_label(next_hour_24)))
        }
        38..=42 => {
            Some(format!("twenty to {}", hour_label(next_hour_24)))
        }
        43..=47 => {
            Some(format!("quarter to {}", hour_label(next_hour_24)))
        }
        48..=52 => {
            Some(format!("ten to {}", hour_label(next_hour_24)))
        }
        53..=57 => {
            Some(format!("five to {}", hour_label(next_hour_24)))
        }
        _ => None,
    };
    result.ok_or_else(|| "Failed to convert to fuzzy time".to_string())
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_to_fuzzy_time() {
        let tests = vec![
            ((14, 0, false), "two o'clock"),
            ((14, 5, false), "five past two"),
            ((14, 10, false), "ten past two"),
            ((14, 15, false), "quarter past two"),
            ((14, 20, false), "twenty past two"),
            ((14, 25, false), "twenty-five past two"),
            ((14, 30, false), "half past two"),
            ((14, 35, false), "twenty-five to three"),
            ((14, 40, false), "twenty to three"),
            ((14, 45, false), "quarter to three"),
            ((14, 50, false), "ten to three"),
            ((14, 55, false), "five to three"),
            ((14, 58, false), "five to three"),
            ((14, 58, true), "five to three"),
            ((14, 59, false), "five to three"),
            ((14, 59, true), "just before three"),
            ((15, 0, false), "three o'clock"),
            ((15, 0, true), "three o'clock"),
            ((15, 1, false), "five past three"),
            ((15, 1, true), "just after three"),
            ((15, 2, false), "five past three"),
            ((15, 2, true), "five past three"),
            ((23, 55, false), "five to midnight"),
            ((23, 59, false), "five to midnight"),
            ((23, 59, true), "just before midnight"),
            ((0, 0, false), "midnight"),
            ((0, 1, false), "five past midnight"),
            ((0, 1, true), "just after midnight"),
            ((11, 55, false), "five to twelve"),
            ((11, 59, false), "five to twelve"),
            ((11, 59, true), "just before twelve"),
            ((12, 0, false), "twelve o'clock"),
            ((12, 0, true), "twelve o'clock"),
            ((12, 1, false), "five past twelve"),
            ((12, 1, true), "just after twelve"),
        ];
        for ((hour, minute, just), expected) in tests {
            let result = convert_to_fuzzy_time(hour, minute, just).unwrap();
            assert_eq!(result, expected);
        }
    }

    #[test]
    fn test_parse_input_time() {
        let tests = vec![
            ("14:30", Ok((14, 30))),
            ("00:00", Ok((0, 0))),
            ("23:59", Ok((23, 59))),
            ("12:15", Ok((12, 15))),
            ("24:00", Err("Hour must be between 0-23 and minute between 0-59".to_string())),
            ("12:60", Err("Hour must be between 0-23 and minute between 0-59".to_string())),
            ("invalid", Err("Input time must be in HH:MM format".to_string())),
        ];
        for (input, expected) in tests {
            let result = parse_input_time(input);
            assert_eq!(result, expected);
        }
    }
}