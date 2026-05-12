# TCP JSON Bridge Prototype

PC-side harness for a future KAREL TCP socket service.

The prototype sends one JSON object terminated by a newline, then reads one newline-terminated JSON response.

Example:

```powershell
python .\prototypes\tcp-json-bridge\fanuc_bridge_client.py --host 192.168.5.10 --port 60010 --type ping
```

This is not used for TP upload or program execution. It is a communication harness only.
