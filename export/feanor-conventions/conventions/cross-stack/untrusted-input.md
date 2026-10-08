---
type: convention
title: Untrusted Input — SSRF, Uploads, Deserialization, Path Traversal
description: Rules for input that reaches a fetcher, a parser, or the filesystem — outbound URL allowlisting, file upload validation, safe deserialization, and path containment for Go, Python, and TypeScript.
applies_to: [go, python, typescript]
tags: [ssrf, file-upload, deserialization, path-traversal, input-validation, security, owasp-a03, owasp-a10]
---

# Untrusted Input

`security.md` covers injection into queries, shells, and HTML. This file covers the three other places untrusted input becomes execution: a URL the server fetches, a file the server stores, and a payload the server deserialises.

## SSRF — Server-Side Request Forgery

Any outbound request whose URL is influenced by user input is an SSRF sink: webhook registration, "import from URL", avatar-by-URL, PDF/screenshot rendering, link previews, OAuth redirect handling, and any admin-configurable callback.

- **Allowlist, never blocklist.** Blocklists lose to decimal IPs (`http://2130706433/`), IPv6-mapped IPv4 (`http://[::ffff:127.0.0.1]/`), `0.0.0.0`, rebinding DNS, and shortener redirects. Name the hosts or domains permitted for each feature.
- **Resolve, then validate, then connect to the resolved address.** Validating a hostname and letting the HTTP client resolve it again is a TOCTOU window (DNS rebinding). Resolve the name yourself, reject private/loopback/link-local/multicast results, and dial the address you checked.
- **Block cloud metadata explicitly**: `169.254.169.254`, `fd00:ec2::254`, `metadata.google.internal`. These return credentials.
- **Do not follow redirects by default.** If a feature requires them, cap the count and re-run the full validation on every hop — validation on hop 0 only is no validation.
- **Restrict the scheme** to `https` (and `http` only when deliberate). Reject `file://`, `gopher://`, `ftp://`, `data:`.
- Give the outbound client its own **short timeout and response size cap**, and where the platform allows it, a dedicated egress path so a bypass still cannot reach internal services.
- Never reflect the raw upstream response body or error to the caller — that turns SSRF into an internal-network read primitive.

```python
# app/utils/safe_fetch.py — resolve, validate, then connect to the checked address.
import ipaddress, socket
import httpx

ALLOWED_SCHEMES = {"https"}

def assert_public_address(host: str) -> str:
    infos = socket.getaddrinfo(host, None)
    addresses = {info[4][0] for info in infos}
    for raw in addresses:
        ip = ipaddress.ip_address(raw)
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
            raise ValueError(f"blocked address for host {host}: {ip}")
    return next(iter(addresses))
```

## File Upload

- **Cap size at the edge**, before the body is buffered — a limit enforced only after reading the whole request is a memory-exhaustion vector, not a limit.
- **Validate content, not the filename.** Check magic bytes / sniffed type against an allowlist of accepted types. A `Content-Type` header and a `.png` extension are both caller-controlled.
- **Never trust the supplied filename.** Generate your own (UUID) for storage. If the original must be kept, store it as metadata, and strip path separators, `..`, control characters, and leading dots before any display.
- **Store outside the web root**, on object storage or a directory that is not statically served. A file that can be uploaded and then fetched back from the same origin is stored XSS.
- **Never make an uploaded file executable**, and never let the stored path or extension decide how it is handled.
- **Serve downloads with `Content-Disposition: attachment`** and `X-Content-Type-Options: nosniff`, from a separate domain where feasible, so a crafted file cannot execute against your origin.
- Scan for malware where uploads are shared between users or leave the system.
- Images that get resized or re-encoded go through a hardened decoder path with explicit dimension and pixel-count caps — decompression bombs are a denial-of-service vector.

## Deserialization

- **Never deserialise an untrusted payload into arbitrary objects.** Format-driven object construction is remote code execution, not a parsing bug.
- Python: `yaml.safe_load`, never `yaml.load` with an unsafe loader. Never `pickle`, `marshal`, `shelve`, `dill`, or `jsonpickle` on anything that crossed a trust boundary — not for caches, not for sessions, not for queue messages.
- TypeScript: `JSON.parse` is safe; `eval`, `new Function`, and `vm` on request data are not. Guard against prototype pollution when merging parsed objects — reject `__proto__`, `constructor`, and `prototype` keys, or use a `Map`/null-prototype object.
- Go: `encoding/json` into a **typed struct**, never `map[string]any` that is then reflected over. Cap `http.MaxBytesReader` on the body. `encoding/gob` is not safe on untrusted input.
- XML anywhere: **disable external entity resolution and DTDs** (XXE). Python: `defusedxml`. Go: `encoding/xml` does not resolve entities — do not add a custom resolver. Node: disable entity expansion in whichever parser is used.
- **Parse into a declared schema, then work with the result.** Pydantic model, Zod schema, or Go struct — the schema is the allowlist. See `access-control.md` for why the schema must also exclude caller-unwritable fields.

## Path Traversal

- **Never join user input onto a base path and open the result.** `../` is only the most obvious form; encoded variants, absolute paths, symlinks, and (on Windows) alternate data streams and drive-relative paths all bypass a naive prefix check.
- Resolve the final path, then confirm it is still inside the allowed root before opening it.
- Prefer never accepting a path at all: take an id, look up the real location internally.

```go
// Go 1.24+: os.Root scopes every operation to the directory, so traversal
// cannot escape it — the check cannot be forgotten at a later call site.
root, err := os.OpenRoot("/srv/uploads")
if err != nil { return err }
defer root.Close()
f, err := root.Open(userSuppliedName) // escapes are refused by the runtime
```

```python
from pathlib import Path

BASE = Path("/srv/uploads").resolve()

def safe_path(user_supplied: str) -> Path:
    candidate = (BASE / user_supplied).resolve()
    if not candidate.is_relative_to(BASE):   # after resolve: symlinks included
        raise ValueError("path escapes upload root")
    return candidate
```

## Testing

Each rule above needs a test that supplies the hostile input and asserts refusal:

- SSRF: `http://169.254.169.254/`, `http://127.0.0.1:22`, a public host that redirects to a private one.
- Upload: a `.png` whose magic bytes are a script, an oversized file, a `../../etc/passwd` filename.
- Deserialization: an unknown-field payload, a `__proto__` key, an XML doc with an external entity.
- Traversal: `../`, an encoded `..%2f`, and an absolute path.

Related: `security.md` (injection, crypto, headers), `access-control.md` (ownership), `api-design.md` (request limits), `data-protection.md` (where uploaded files may be stored).
