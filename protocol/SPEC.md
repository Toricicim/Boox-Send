# BOOX Send Wire Protocol v1

Transport is an authenticated RFCOMM byte stream. Integers are unsigned and
big-endian.

Each frame is:

```
uint32 bodyLength
uint8  type
bytes  payload (bodyLength - 1 bytes)
```

The maximum accepted body length is 1 MiB. JSON payloads are UTF-8. Binary file
chunks are 16 KiB so they can be split safely into RFCOMM MTU-sized writes.

| Type | Name | Payload |
| ---: | --- | --- |
| 1 | HELLO | JSON `Hello` |
| 2 | HELLO_ACK | JSON `HelloAck` |
| 3 | FILE_OFFER | JSON `FileOffer` |
| 4 | FILE_DECISION | JSON `FileDecision` |
| 5 | FILE_CHUNK | 16-byte UUID, uint64 offset, bytes data |
| 6 | FILE_COMMIT | JSON `FileCommit` |
| 7 | FILE_RESULT | JSON `FileResult` |
| 8 | FINISH | Empty |

## Authentication

The user enters the same eight-character setup code on both devices. Both sides
derive `SHA256(UTF8(code.uppercased()))`. The Mac generates a 32-byte nonce and
sends:

```json
{"version":1,"nonce":"base64","proof":"base64(HMAC-SHA256(key, nonce))"}
```

The receiver compares the proof in constant time and replies with
`{"accepted":true,"message":null}`. Bluetooth pairing plus this proof prevents
an unrelated paired device from using the receiver.

Conformance vector: setup code `AB12CD34` and nonce bytes `nonce` produce
Base64 proof `0uJFxA6IH4nZmsuD0uTfTlk47Yp+JZJsdWKkyPAbUaI=`.

## File transaction

`FileOffer` contains `transferId` (UUID), sanitized basename, byte length, and
lowercase SHA-256. The receiver reserves the first unused destination name and
returns it with its resumable offset. A retry with the same transfer ID reuses
the same partial file and destination name.

Chunks must arrive contiguously at the advertised offset. The receiver writes
to `.booxsend-<transferId>.part`. `FILE_COMMIT` is accepted only after size and
SHA-256 verification, then the partial document is renamed to the reserved
destination name.

Completed transfer IDs are retained for seven days. Replaying a completed
transaction returns success without creating a duplicate. A new Finder action
always creates new transfer IDs and therefore a numbered copy.
