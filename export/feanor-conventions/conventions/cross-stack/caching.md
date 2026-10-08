---
type: convention
title: Caching
description: Cache key format, HTTP caching contract, and invalidation strategy for Go, Python, and TypeScript — apply when implementing application-level or HTTP caching in any layer.
applies_to: [go, python, typescript]
tags: [caching, performance]
---

# Caching

## Cross-Stack Rules

- **Cache key format:** `{service}:{domain}:{entity}:{id}[:{qualifier}]` — lowercase, colon-separated, no spaces. Example: `orders:orders:invoice:INV-102:summary`. Identical across all backends sharing a Redis instance to prevent collision.
  - `{service}` — deployable unit name (matters when multiple backends share one cache store).
  - `{domain}` — domain-package name matching project layout.
  - `{entity}` / `{id}` — what is being cached.
  - `{qualifier}` — optional, for a specific view or computation of that entity.
- **HTTP contract (backend → frontend):** every cacheable GET response sets `Cache-Control`, `ETag`, and `Vary` so the frontend attaches to either backend without special-casing language.
  - `Cache-Control: public, max-age={s}, stale-while-revalidate={s}` for cacheable responses; `private, no-store` for user-specific or sensitive data.
  - `ETag` on responses where conditional requests are worthwhile — validate `If-None-Match`, return `304` when unchanged.
  - `Vary` set whenever the response differs by a request header — omitting it causes cache poisoning across users.
  - Never set caching headers on mutation endpoints without `private`/`no-store`.
- **Cache-aside** is the default pattern: check cache, on miss read from source, write to cache, return.
- TTL set explicitly on every write — no unbounded cache entry.
- Invalidate explicitly on the write path when staleness has a real user-visible cost; don't rely on TTL alone.
- No sensitive data in shared (Redis/distributed) caches.

## Go

- **`go-redis`/`rueidis`** for distributed caching (shared across processes or services).
- **`sync.Map`** or a bounded in-memory LRU for cheap process-local caching — don't reach for Redis when the data doesn't need to leave the process.
- Propagate `context.Context` to every cache call — a cache lookup is I/O and must be cancellable/timeoutable.

### Boilerplate

```go
// cache/redis.go
package cache

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/redis/go-redis/v9"
)

type Client struct{ rdb *redis.Client }

func New(rdb *redis.Client) *Client { return &Client{rdb: rdb} }

// Key builds a canonical cache key.
func Key(service, domain, entity, id string, qualifiers ...string) string {
    k := fmt.Sprintf("%s:%s:%s:%s", service, domain, entity, id)
    for _, q := range qualifiers {
        k += ":" + q
    }
    return k
}

func (c *Client) Get(ctx context.Context, key string, dst any) error {
    b, err := c.rdb.Get(ctx, key).Bytes()
    if err != nil {
        return err // caller checks redis.Nil for a cache miss
    }
    return json.Unmarshal(b, dst)
}

func (c *Client) Set(ctx context.Context, key string, val any, ttl time.Duration) error {
    b, err := json.Marshal(val)
    if err != nil {
        return err
    }
    return c.rdb.Set(ctx, key, b, ttl).Err()
}

func (c *Client) Del(ctx context.Context, keys ...string) error {
    return c.rdb.Del(ctx, keys...).Err()
}
```

## Python

- **`redis-py`** (async client) for distributed caching — not an in-process dict, which breaks the moment there is more than one process.
- **`functools.lru_cache`** or **`cachetools`** for cheap process-local caching (config values, small lookup tables).

### Boilerplate

```python
# app/cache/redis.py
import json
from typing import Any
from redis.asyncio import Redis

def cache_key(service: str, domain: str, entity: str, id_: str, *qualifiers: str) -> str:
    parts = [service, domain, entity, id_, *qualifiers]
    return ":".join(parts)

class CacheClient:
    def __init__(self, redis: Redis) -> None:
        self._r = redis

    async def get(self, key: str) -> Any | None:
        raw = await self._r.get(key)
        return json.loads(raw) if raw is not None else None

    async def set(self, key: str, value: Any, ttl_seconds: int) -> None:
        await self._r.setex(key, ttl_seconds, json.dumps(value))

    async def delete(self, *keys: str) -> None:
        if keys:
            await self._r.delete(*keys)
```

## TypeScript

- Next.js consumes the HTTP caching contract set by the backend — no special-casing per backend language.
- Use `fetch()` extended options in Server Components/Server Actions; do not fight the framework's cache.
- Tag names mirror backend cache key domains (`orders`, `orders:invoice:INV-102`) so invalidation targets the same conceptual entity on both layers.
- No client-side cache library (React Query / SWR) by default — Server Components + fetch cache cover most needs. Add one only when genuine client-side polling from a Client Component is required.

### Boilerplate

```typescript
// Server Component data fetch with tag-based caching
async function getInvoice(id: string) {
  const res = await fetch(`${process.env.API_URL}/invoices/${id}`, {
    next: { tags: [`orders:invoice:${id}`] },
  });
  if (!res.ok) throw new Error("Failed to fetch invoice");
  return res.json();
}

// Server Action: invalidate after mutation
// app/actions/invoices.ts
"use server";
import { revalidateTag } from "next/cache";

export async function updateInvoice(id: string, data: unknown) {
  const res = await fetch(`${process.env.API_URL}/invoices/${id}`, {
    method: "PATCH",
    body: JSON.stringify(data),
    headers: { "Content-Type": "application/json" },
  });
  if (!res.ok) throw new Error("Update failed");
  revalidateTag(`orders:invoice:${id}`);
}

// Route segment: ISR-style revalidation
// app/invoices/[id]/page.tsx
export const revalidate = 60; // seconds — set explicitly, never rely on defaults
```
