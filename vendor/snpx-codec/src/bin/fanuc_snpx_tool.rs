//! Small command-line wrapper around the local SNPX codec.
//!
//! Project workflow should prefer the PowerShell allowlist tools for write
//! planning. This binary exists so live read/write execution can be wired
//! without reimplementing the SNPX wire protocol in PowerShell.

use std::env;
use std::fs;
use std::process;

use bytes::Bytes;
use snpx_codec::{
    ByteSelector, Client, FanucAddr, Port, Request, Response, TcpTransport, WordSelector,
};

#[tokio::main]
async fn main() {
    if let Err(err) = run().await {
        eprintln!("{err}");
        process::exit(1);
    }
}

async fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        print_help();
        return Ok(());
    }

    let host = option_value(&args, "--host").unwrap_or_else(|| "192.168.0.10:60008".to_string());
    let port = match option_value(&args, "--port-kind")
        .unwrap_or_else(|| "fanuc-snpx".to_string())
        .as_str()
    {
        "fanuc-snpx" => Port::FanucSnpx,
        "srtp" => Port::Srtp,
        other => return Err(format!("unsupported --port-kind '{other}'")),
    };

    let op = args
        .first()
        .ok_or_else(|| "missing operation; use --help".to_string())?;

    let transport = TcpTransport::connect(&host)
        .await
        .map_err(|err| format!("connect failed for {host}: {err}"))?;
    let mut client = Client::connect(transport, port)
        .await
        .map_err(|err| format!("SNPX handshake failed for {host}: {err}"))?;

    match op.as_str() {
        "probe" => {
            let time = client
                .request(Request::GetTime)
                .await
                .map_err(|err| format!("GetTime failed: {err}"))?;
            println!(
                "{{\"ok\":true,\"operation\":\"probe\",\"host\":\"{}\",\"time\":{}}}",
                json_escape(&host),
                response_json(&time)
            );
        }
        "read-r" => {
            let start = required_u16(&args, "--start")?;
            let count = required_u16(&args, "--count")?;
            let words = read_r_words(&mut client, start, count).await?;
            println!(
                "{{\"ok\":true,\"operation\":\"read-r\",\"host\":\"{}\",\"start\":{},\"count\":{},\"words\":[{}]}}",
                json_escape(&host),
                start,
                count,
                join_i16(&words)
            );
        }
        "asg-read" => {
            let setup_file = option_value(&args, "--setup-file")
                .ok_or_else(|| "asg-read requires --setup-file".to_string())?;
            let start = required_u16(&args, "--start")?;
            let count = required_u16(&args, "--count")?;
            let commands = read_setup_commands(&setup_file)?;

            write_g_command(&mut client, "CLRASG").await?;
            for command in &commands {
                write_g_command(&mut client, command).await?;
            }

            let words = read_r_words(&mut client, start, count).await?;
            println!(
                "{{\"ok\":true,\"operation\":\"asg-read\",\"host\":\"{}\",\"setupFile\":\"{}\",\"setasgCount\":{},\"start\":{},\"count\":{},\"words\":[{}]}}",
                json_escape(&host),
                json_escape(&setup_file),
                commands.len(),
                start,
                count,
                join_i16(&words)
            );
        }
        "asg-write-r" => {
            require_write_ack(&args)?;
            let setup_file = option_value(&args, "--setup-file")
                .ok_or_else(|| "asg-write-r requires --setup-file".to_string())?;
            let start = required_u16(&args, "--start")?;
            let value = required_i32(&args, "--value")?;
            let commands = read_setup_commands(&setup_file)?;

            write_g_command(&mut client, "CLRASG").await?;
            for command in &commands {
                write_g_command(&mut client, command).await?;
            }

            let before = read_r_words(&mut client, start, 2).await?;
            let bytes = value.to_le_bytes();
            let response = client
                .request(Request::WriteSysWords {
                    selector: WordSelector::R,
                    addr: FanucAddr::from_raw(start),
                    words: Bytes::copy_from_slice(&bytes),
                })
                .await
                .map_err(|err| format!("asg-write-r failed: {err}"))?;
            match response {
                Response::WriteOk => {}
                other => {
                    return Err(format!(
                        "asg-write-r returned unexpected response: {other:?}"
                    ))
                }
            }
            let after = read_r_words(&mut client, start, 2).await?;
            println!(
                "{{\"ok\":true,\"operation\":\"asg-write-r\",\"host\":\"{}\",\"setupFile\":\"{}\",\"setasgCount\":{},\"start\":{},\"value\":{},\"before\":[{}],\"after\":[{}]}}",
                json_escape(&host),
                json_escape(&setup_file),
                commands.len(),
                start,
                value,
                join_i16(&before),
                join_i16(&after)
            );
        }
        "asg-read-ualm-severity" => {
            let setup_file = option_value(&args, "--setup-file")
                .ok_or_else(|| "asg-read-ualm-severity requires --setup-file".to_string())?;
            let start = required_u16(&args, "--start")?;
            let commands = read_setup_commands(&setup_file)?;

            write_g_command(&mut client, "CLRASG").await?;
            for command in &commands {
                write_g_command(&mut client, command).await?;
            }

            let words = read_r_words(&mut client, start, 2).await?;
            let severity = decode_ualm_severity_words(&words)?;
            println!(
                "{{\"ok\":true,\"operation\":\"asg-read-ualm-severity\",\"host\":\"{}\",\"setupFile\":\"{}\",\"setasgCount\":{},\"start\":{},\"words\":[{}],\"severity\":{},\"severityName\":\"{}\"}}",
                json_escape(&host),
                json_escape(&setup_file),
                commands.len(),
                start,
                join_i16(&words),
                severity.value,
                severity.name
            );
        }
        "asg-write-ualm-severity" => {
            require_write_ack(&args)?;
            let setup_file = option_value(&args, "--setup-file")
                .ok_or_else(|| "asg-write-ualm-severity requires --setup-file".to_string())?;
            let start = required_u16(&args, "--start")?;
            let severity_text = option_value(&args, "--severity")
                .ok_or_else(|| "asg-write-ualm-severity requires --severity".to_string())?;
            let severity = parse_ualm_severity(&severity_text)?;
            let commands = read_setup_commands(&setup_file)?;

            write_g_command(&mut client, "CLRASG").await?;
            for command in &commands {
                write_g_command(&mut client, command).await?;
            }

            let before = read_r_words(&mut client, start, 2).await?;
            let before_severity = decode_ualm_severity_words(&before)?;
            let bytes = [severity.value, 0u8];
            let response = client
                .request(Request::WriteSysWords {
                    selector: WordSelector::R,
                    addr: FanucAddr::from_raw(start),
                    words: Bytes::copy_from_slice(&bytes),
                })
                .await
                .map_err(|err| format!("asg-write-ualm-severity failed: {err}"))?;
            match response {
                Response::WriteOk => {}
                other => {
                    return Err(format!(
                        "asg-write-ualm-severity returned unexpected response: {other:?}"
                    ))
                }
            }
            let after = read_r_words(&mut client, start, 2).await?;
            let after_severity = decode_ualm_severity_words(&after)?;
            if after_severity.value != severity.value {
                return Err(format!(
                    "asg-write-ualm-severity readback mismatch: requested {} ({}) but got {} ({})",
                    severity.value, severity.name, after_severity.value, after_severity.name
                ));
            }
            println!(
                "{{\"ok\":true,\"operation\":\"asg-write-ualm-severity\",\"host\":\"{}\",\"setupFile\":\"{}\",\"setasgCount\":{},\"start\":{},\"requestedSeverity\":{},\"requestedSeverityName\":\"{}\",\"beforeWords\":[{}],\"beforeSeverity\":{},\"beforeSeverityName\":\"{}\",\"afterWords\":[{}],\"afterSeverity\":{},\"afterSeverityName\":\"{}\"}}",
                json_escape(&host),
                json_escape(&setup_file),
                commands.len(),
                start,
                severity.value,
                severity.name,
                join_i16(&before),
                before_severity.value,
                before_severity.name,
                join_i16(&after),
                after_severity.value,
                after_severity.name
            );
        }
        "asg-write-r-text" => {
            require_write_ack(&args)?;
            let setup_file = option_value(&args, "--setup-file")
                .ok_or_else(|| "asg-write-r-text requires --setup-file".to_string())?;
            let start = required_u16(&args, "--start")?;
            let text = option_value(&args, "--text")
                .ok_or_else(|| "asg-write-r-text requires --text".to_string())?;
            let word_count = option_value(&args, "--word-count")
                .unwrap_or_else(|| "30".to_string())
                .parse::<u16>()
                .map_err(|err| format!("invalid --word-count: {err}"))?;
            if !text.is_ascii() {
                return Err("asg-write-r-text only supports ASCII text".to_string());
            }
            let max_bytes = word_count as usize * 2;
            if text.as_bytes().len() > max_bytes {
                return Err(format!(
                    "asg-write-r-text text is {} bytes, but projection holds {max_bytes} bytes",
                    text.as_bytes().len()
                ));
            }
            let commands = read_setup_commands(&setup_file)?;

            write_g_command(&mut client, "CLRASG").await?;
            for command in &commands {
                write_g_command(&mut client, command).await?;
            }

            let before = read_r_words(&mut client, start, word_count).await?;
            let mut bytes = vec![0u8; max_bytes];
            bytes[..text.as_bytes().len()].copy_from_slice(text.as_bytes());
            let response = client
                .request(Request::WriteSysWords {
                    selector: WordSelector::R,
                    addr: FanucAddr::from_raw(start),
                    words: Bytes::from(bytes),
                })
                .await
                .map_err(|err| format!("asg-write-r-text failed: {err}"))?;
            match response {
                Response::WriteOk => {}
                other => {
                    return Err(format!(
                        "asg-write-r-text returned unexpected response: {other:?}"
                    ))
                }
            }
            let after = read_r_words(&mut client, start, word_count).await?;
            println!(
                "{{\"ok\":true,\"operation\":\"asg-write-r-text\",\"host\":\"{}\",\"setupFile\":\"{}\",\"setasgCount\":{},\"start\":{},\"wordCount\":{},\"text\":\"{}\",\"before\":[{}],\"after\":[{}]}}",
                json_escape(&host),
                json_escape(&setup_file),
                commands.len(),
                start,
                word_count,
                json_escape(&text),
                join_i16(&before),
                join_i16(&after)
            );
        }
        "write-r" => {
            require_write_ack(&args)?;
            let start = required_u16(&args, "--start")?;
            let value = required_i32(&args, "--value")?;
            let bytes = value.to_le_bytes();
            let response = client
                .request(Request::WriteSysWords {
                    selector: WordSelector::R,
                    addr: FanucAddr::from_raw(start),
                    words: Bytes::copy_from_slice(&bytes),
                })
                .await
                .map_err(|err| format!("write-r failed: {err}"))?;
            match response {
                Response::WriteOk => {
                    println!(
                        "{{\"ok\":true,\"operation\":\"write-r\",\"host\":\"{}\",\"start\":{},\"value\":{}}}",
                        json_escape(&host),
                        start,
                        value
                    );
                }
                other => return Err(format!("write-r returned unexpected response: {other:?}")),
            }
        }
        "command-g" => {
            require_write_ack(&args)?;
            let text = option_value(&args, "--text")
                .ok_or_else(|| "command-g requires --text".to_string())?;
            let response = client
                .request(Request::WriteSysBytes {
                    selector: ByteSelector::G,
                    addr: FanucAddr::from_raw(1),
                    bytes: Bytes::copy_from_slice(text.as_bytes()),
                })
                .await
                .map_err(|err| format!("command-g failed: {err}"))?;
            match response {
                Response::WriteOk => {
                    println!(
                        "{{\"ok\":true,\"operation\":\"command-g\",\"host\":\"{}\",\"text\":\"{}\"}}",
                        json_escape(&host),
                        json_escape(&text)
                    );
                }
                other => return Err(format!("command-g returned unexpected response: {other:?}")),
            }
        }
        other => return Err(format!("unknown operation '{other}'; use --help")),
    }

    Ok(())
}

fn print_help() {
    println!(
        "fanuc-snpx-tool\n\
\n\
Usage:\n\
  fanuc-snpx-tool probe [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool read-r --start N --count N [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool asg-read --setup-file PATH --start N --count N [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool asg-write-r --setup-file PATH --start N --value I32 --i-accept-live-write [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool asg-read-ualm-severity --setup-file PATH --start N [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool asg-write-ualm-severity --setup-file PATH --start N --severity WARN|STOP.L|STOP.G|ABORT.L|ABORT.G --i-accept-live-write [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool asg-write-r-text --setup-file PATH --start N --text TEXT [--word-count N] --i-accept-live-write [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool write-r --start N --value I32 --i-accept-live-write [--host 192.168.0.10:60008]\n\
  fanuc-snpx-tool command-g --text TEXT --i-accept-live-write [--host 192.168.0.10:60008]\n\
\n\
Writes are intentionally gated. Normal project write flow should use the PowerShell allowlist tools first."
    );
}

async fn read_r_words(
    client: &mut Client<TcpTransport>,
    start: u16,
    count: u16,
) -> Result<Vec<i16>, String> {
    let response = client
        .request(Request::ReadSysWords {
            selector: WordSelector::R,
            addr: FanucAddr::from_raw(start),
            count,
        })
        .await
        .map_err(|err| format!("read-r failed: {err}"))?;
    match response {
        Response::ReadWords { words } => Ok(decode_i16_words(words.as_ref())),
        other => Err(format!("read-r returned unexpected response: {other:?}")),
    }
}

async fn write_g_command(client: &mut Client<TcpTransport>, command: &str) -> Result<(), String> {
    let response = client
        .request(Request::WriteSysBytes {
            selector: ByteSelector::G,
            addr: FanucAddr::from_raw(1),
            bytes: Bytes::copy_from_slice(command.as_bytes()),
        })
        .await
        .map_err(|err| format!("command-g failed for '{command}': {err}"))?;
    match response {
        Response::WriteOk => Ok(()),
        other => Err(format!(
            "command-g for '{command}' returned unexpected response: {other:?}"
        )),
    }
}

fn read_setup_commands(path: &str) -> Result<Vec<String>, String> {
    let text = fs::read_to_string(path)
        .map_err(|err| format!("failed to read setup file '{path}': {err}"))?;
    let commands: Vec<String> = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(str::to_string)
        .collect();
    if commands.is_empty() {
        return Err(format!(
            "setup file '{path}' did not contain SETASG commands"
        ));
    }
    for command in &commands {
        if !command.starts_with("SETASG ") {
            return Err(format!("setup command is not SETASG: '{command}'"));
        }
    }
    Ok(commands)
}

fn option_value(args: &[String], name: &str) -> Option<String> {
    args.windows(2)
        .find(|window| window[0] == name)
        .map(|window| window[1].clone())
}

fn required_u16(args: &[String], name: &str) -> Result<u16, String> {
    option_value(args, name)
        .ok_or_else(|| format!("missing {name}"))?
        .parse::<u16>()
        .map_err(|err| format!("invalid {name}: {err}"))
}

fn required_i32(args: &[String], name: &str) -> Result<i32, String> {
    option_value(args, name)
        .ok_or_else(|| format!("missing {name}"))?
        .parse::<i32>()
        .map_err(|err| format!("invalid {name}: {err}"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct UalmSeverity {
    value: u8,
    name: &'static str,
}

fn parse_ualm_severity(input: &str) -> Result<UalmSeverity, String> {
    let normalized = input.trim().to_ascii_uppercase();
    match normalized.as_str() {
        "0" | "WARN" => Ok(UalmSeverity {
            value: 0,
            name: "WARN",
        }),
        "6" | "STOP.L" | "STOPL" | "STOP_L" => Ok(UalmSeverity {
            value: 6,
            name: "STOP.L",
        }),
        "38" | "STOP.G" | "STOPG" | "STOP_G" => Ok(UalmSeverity {
            value: 38,
            name: "STOP.G",
        }),
        "11" | "ABORT.L" | "ABORTL" | "ABORT_L" => Ok(UalmSeverity {
            value: 11,
            name: "ABORT.L",
        }),
        "43" | "ABORT.G" | "ABORTG" | "ABORT_G" => Ok(UalmSeverity {
            value: 43,
            name: "ABORT.G",
        }),
        _ => Err(format!(
            "unsupported UALM severity '{input}'; allowed values are 0/WARN, 6/STOP.L, 38/STOP.G, 11/ABORT.L, 43/ABORT.G"
        )),
    }
}

fn decode_ualm_severity_words(words: &[i16]) -> Result<UalmSeverity, String> {
    if words.len() < 2 {
        return Err(
            "UALM severity readback must include two words for guard validation".to_string(),
        );
    }
    let first = words[0] as u16;
    let second = words[1] as u16;
    let value = (first & 0x00ff) as u8;
    let upper_byte = first >> 8;
    if upper_byte != 0 || second != 0 {
        return Err(format!(
            "UALM severity projection has unexpected upper data: words=[{},{}], lowByte={value}, upperByte={upper_byte}, secondWord={second}",
            words[0], words[1]
        ));
    }
    parse_ualm_severity(&value.to_string())
}

fn require_write_ack(args: &[String]) -> Result<(), String> {
    if args.iter().any(|arg| arg == "--i-accept-live-write") {
        Ok(())
    } else {
        Err("live write operation requires --i-accept-live-write".to_string())
    }
}

fn decode_i16_words(bytes: &[u8]) -> Vec<i16> {
    bytes
        .chunks_exact(2)
        .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
        .collect()
}

fn join_i16(words: &[i16]) -> String {
    words
        .iter()
        .map(std::string::ToString::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

fn response_json(response: &Response) -> String {
    match response {
        Response::Time { hh, mm, ss } => {
            format!("{{\"hh\":{hh},\"mm\":{mm},\"ss\":{ss}}}")
        }
        other => format!("{{\"raw\":\"{}\"}}", json_escape(&format!("{other:?}"))),
    }
}

fn json_escape(input: &str) -> String {
    input
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ualm_severity_accepts_known_values_and_names() {
        assert_eq!(
            parse_ualm_severity("WARN").unwrap(),
            UalmSeverity {
                value: 0,
                name: "WARN"
            }
        );
        assert_eq!(
            parse_ualm_severity("43").unwrap(),
            UalmSeverity {
                value: 43,
                name: "ABORT.G"
            }
        );
        assert_eq!(
            parse_ualm_severity("stop_g").unwrap(),
            UalmSeverity {
                value: 38,
                name: "STOP.G"
            }
        );
    }

    #[test]
    fn ualm_severity_rejects_unknown_values() {
        let err = parse_ualm_severity("7").expect_err("unexpected severity must fail");
        assert!(err.contains("unsupported UALM severity"));
    }

    #[test]
    fn ualm_severity_decodes_low_byte_and_requires_clean_upper_data() {
        assert_eq!(
            decode_ualm_severity_words(&[43, 0]).unwrap(),
            UalmSeverity {
                value: 43,
                name: "ABORT.G"
            }
        );
        assert!(decode_ualm_severity_words(&[0x0106, 0]).is_err());
        assert!(decode_ualm_severity_words(&[6, 1]).is_err());
    }
}
