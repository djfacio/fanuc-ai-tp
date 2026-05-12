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

    let host = option_value(&args, "--host").unwrap_or_else(|| "192.168.5.10:60008".to_string());
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
  fanuc-snpx-tool probe [--host 192.168.5.10:60008]\n\
  fanuc-snpx-tool read-r --start N --count N [--host 192.168.5.10:60008]\n\
  fanuc-snpx-tool asg-read --setup-file PATH --start N --count N [--host 192.168.5.10:60008]\n\
  fanuc-snpx-tool asg-write-r --setup-file PATH --start N --value I32 --i-accept-live-write [--host 192.168.5.10:60008]\n\
  fanuc-snpx-tool write-r --start N --value I32 --i-accept-live-write [--host 192.168.5.10:60008]\n\
  fanuc-snpx-tool command-g --text TEXT --i-accept-live-write [--host 192.168.5.10:60008]\n\
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
        return Err(format!("setup file '{path}' did not contain SETASG commands"));
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
