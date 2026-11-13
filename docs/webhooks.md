# Webhooks

The bot can talk to other systems over plain HTTP in two directions. Both are **off by default**.

| Direction | Config section | What it does |
|-----------|----------------|--------------|
| Out | `[Event_Webhooks]` | POSTs selected mesh events to URLs you choose |
| In | `[Webhook]` | Listens for HTTP POSTs and sends what they contain as a mesh message |

> **Warning — read this before turning either one on.**
>
> **Outbound:** every selected event leaves this computer. Channel messages carry their text, sender names and signal data, and webhook URLs often contain a token. Only send to endpoints you control or trust, prefer `https`, and leave `include_dm_text = false` unless you mean to forward private messages.
>
> **Inbound:** this opens a door into your mesh. Anything that can reach the port (and knows the token) can make the bot transmit as itself. Keep `host = 127.0.0.1` unless you need it elsewhere. On any other address the bot **will not start the listener without `secret_token`**. Firewall the port, and never forward it from your router to the internet.

## Outbound event webhooks

```ini
[Event_Webhooks]
enabled = true
urls = https://example.com/mesh-hook
events = message_received,node_seen,command_run
secret = a-long-random-value
include_dm_text = false
# channels = general,alerts
node_seen_interval_seconds = 300
timeout_seconds = 5
```

### Events

| Event | Sent when | `data` fields |
|-------|-----------|---------------|
| `message_received` | A channel message or DM reaches the bot | `channel`, `is_dm`, `sender`, `sender_pubkey`, `text`, `hops`, `path`, `snr`, `rssi`, `timestamp` |
| `node_seen` | An advert is tracked (duplicate copies of one advert are ignored; each node at most once per `node_seen_interval_seconds`) | `public_key`, `name`, `role`, `device_type`, `first_seen`, `hops`, `snr`, `rssi`, `latitude`, `longitude` |
| `command_run` | The bot runs a command for someone | `command`, `ok`, `channel`, `is_dm`, `sender`, `sender_pubkey`, `text`, `response` |

For DMs, `text` (and `response` for DM commands) is `null` unless `include_dm_text = true`. `channels` limits `message_received` to the listed channels.

### Request

```http
POST /mesh-hook HTTP/1.1
Content-Type: application/json
X-MeshCore-Event: command_run
X-MeshCore-Signature: sha256=3b1f…

{"event":"command_run","sent_at":"2026-11-13T18:00:00+00:00","bot":"MyBot",
 "data":{"command":"wx","ok":true,"channel":"general","sender":"Al", …}}
```

`X-MeshCore-Signature` is present only when `secret` is set. It is the hex HMAC-SHA256 of the raw request body, keyed with `secret`. Check it on the receiving side before trusting the request, for example in Python:

```python
import hashlib, hmac

def verified(body: bytes, header: str, secret: str) -> bool:
    expected = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header or "")
```

### Delivery

Best effort. Events wait in a small in-memory queue (the oldest is dropped if 200 are waiting). Each URL gets one retry after a network error or a 5xx reply. A 4xx reply is not retried. Redirects are not followed. Nothing here can delay the bot's own mesh handling. Logs show only the scheme and host of a URL, never its path or query.

## Inbound webhook

See the `[Webhook]` section in `config.ini.example` for every option. In short:

```ini
[Webhook]
enabled = true
host = 127.0.0.1
port = 8765
secret_token = a-long-random-value
```

```bash
curl -X POST http://127.0.0.1:8765/webhook \
  -H "Authorization: Bearer a-long-random-value" \
  -H "Content-Type: application/json" \
  -d '{"channel": "general", "message": "Hello from a script"}'
```
