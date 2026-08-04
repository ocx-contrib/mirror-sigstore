# mirror-sigstore

OCX mirror for [cosign](https://github.com/sigstore/cosign), the container and
artifact signing tool published by the [Sigstore](https://www.sigstore.dev)
project. One repository, one spec directory per package.

| Package | Spec | Publishes to | Announced as | Upstream SPDX |
|---|---|---|---|---|
| [cosign](https://github.com/sigstore/cosign) | [`cosign/mirror.yml`](cosign/mirror.yml) | `ghcr.io/ocx-contrib/sigstore/cosign` | [`ocx.sh/sigstore/cosign`](https://index.ocx.sh/sigstore/cosign) | `Apache-2.0` |

Each upstream release is discovered, re-bundled, smoke-tested per
`(version, platform)` and only then pushed with cascade tags, after which the
result is announced into the OCX index.

`sigstore` is the project's own brand and it publishes several tools (cosign,
rekor, fulcio, gitsign, policy-controller), so the org names the namespace and
this repo is sized for more than one package from day one.

## Layout

```
mirror-base.yml         repo-wide policy every spec inherits via `extends:`
cosign/
├── mirror.yml          the spec — never at the repo root
├── metadata.json       bundle interface
├── CATALOG.md          → ocx package describe
├── logo.svg / logo.png describe assets, 512px PNG
└── tests/smoke.star    Starlark smoke test
```

`LICENSE` and `NOTICE.md` are shared at the root. Logos are **not** — each
package carries its own, because a repo-root `logo.*` sits in no workflow's
`paths:` filter, so replacing it would publish nothing until some unrelated
edit happened to fire.

⚠️ `extends:` is a **shallow** merge of top-level keys. A spec that restates
`platforms:` to change one runner drops every `containers:` entry with it, and
nothing reds — the legs simply stop existing, and every `os.features` claim
goes back to being asserted rather than verified. Restate a block in full or
not at all. `cosign/mirror.yml` does not restate it at all, which removes the
trap structurally. A second package added here must **measure its own** libc
matrix rather than inherit cosign's.

## The v3-only release train

cosign maintains **two major lines at once** — v3.x (current) and v2.x (LTS) —
and releases them on overlapping dates. The newest five releases by publish
date are `v3.1.2, v2.6.4, v3.1.1, v3.0.6, v2.6.3`: a mix. `tag_pattern` is
therefore anchored to major 3 (`^v(?P<version>3\.\d+\.\d+)$`), and version
ordering is by **parsed semver, never by `published_at`**. Mirroring the v2 LTS
line would be a separate package decision, not a change to this one.

The mirrored range is `3.0.6`, `3.1.1`, `3.1.2` — three releases spanning two
minors, because upstream published no `v3.0.0` and no `v3.1.0` at all (both 404
on the releases API).

## Platforms

`cosign` publishes five platform entries: both Linux arches, both macOS arches
and `windows/amd64`. Upstream ships one Go binary per platform with no
musl/gnu split, and **all six** declared Linux artifacts were byte-measured —
two arches × all three mirrored versions: no `PT_INTERP`, no `DT_NEEDED`.

UPX was explicitly ruled out rather than assumed: a packer stub leaves no
program headers and no section headers, which would make `file` call a
glibc-dynamic binary "statically linked" and turn the measurement above into a
false universality claim. `strings -a | grep -c '^UPX'` returns 1 on two of the
six artifacts, but those hits are `UPXea` and `UPXy` — incidental substrings in
a 130 MB binary, not the `UPX!` magic — and 24 section headers plus intact
`debug_info` settle it. The decisive check does not depend on reading headers
correctly at all: the binaries **run** in `alpine:3.20` and print their version,
where a glibc-dynamic binary exits 127.

`os.features` states what an artifact requires *of the host*, so both Linux keys
are **bare** — `+libc.glibc` would hide the package from Alpine and
`+libc.musl` would hide it from every glibc host it in fact runs on. The
`alpine:3.20` container leg on both arches in `mirror-base.yml` is what turns
that claim into evidence; the measurement transcript is recorded above the
`assets:` block in `cosign/mirror.yml`.

Upstream also publishes `cosign-linux-arm` (32-bit), `ppc64le`, `riscv64` and
`s390x` builds. None maps to an OCX platform key — ocx's architecture enum is
`amd64` and `arm64` only — so none is mirrored. **There is no
`windows/arm64` asset** on any in-range release, so that platform is not
declared: a declared-but-unmatched platform boots a real `windows-11-arm`
runner, self-skips every version and reports success having tested nothing.

### Raw binaries and the prefix-collision trap

Every asset is a **raw uncompressed binary** — no archive layer, no extension
on unix, `.exe` on Windows — served at mode `0644`. There is no `.gz`/`.tar`
twin to mis-select, but there is a prefix collision:

```
cosign-linux-amd64                      <- mirrored
cosign-linux-pivkey-pkcs11key-amd64     <- a DIFFERENT build
```

The `pivkey`/`pkcs11key` variants add hardware PIV / PKCS#11 token support and
link `libpcsclite` at runtime, so they are neither interchangeable with the base
binary nor honestly declarable under a bare `os.features`. Every asset pattern
is therefore **end-anchored**: `^cosign-linux-amd64$` cannot match them, while
`^cosign-linux` would.

Resolution was verified **both ways on every in-range release** (3.0.6, 3.1.1,
3.1.2): each of the five patterns matches exactly one asset out of **83**, every
time, and no other asset matches any pattern. A pattern matching zero would be
silently skipped rather than reported, so this check is not optional. The other
78 assets per release are rpm/deb/apk sidecars across ~10 arches, a
`.sigstore.json` and a `.sbom.json` per binary, `release-cosign.pub` and
`cosign_checksums.txt`.

Asset names carry **no version string**, so the usual "does the filename agree
with the tag" check is inexpressible here. It was replaced with a stronger one:
each downloaded binary was run and asked, and `v3.0.6/cosign-linux-amd64`
reports `GitVersion: v3.0.6`, and so on for all three. No release ships a
previous version's binaries under a new tag.

## Editing

| File | Edit | Regenerate after |
|------|------|------------------|
| `mirror-base.yml`, `cosign/mirror.yml` | hand | yes — see below |
| `cosign/{metadata.json,CATALOG.md,logo.*}` | hand | — |
| `cosign/tests/smoke.star` | hand | — |
| `.github/workflows/*.yml` | **generated — never hand-edit** | re-run when a spec changes |

```bash
ocx-mirror package pipeline generate ci --spec cosign/mirror.yml
```

**Name every spec.** `--spec` *appends* rather than replaces, so a command
naming a subset silently stops rendering the rest while staying green — and the
drift guard reds on a generated workflow the current spec set no longer
produces.

`verify-generated.yml` exits 65 on drift. If a generated workflow is wrong, the
spec or the renderer template is wrong — fix it there and regenerate.

Run `direnv allow` once to put the pinned toolchain on `PATH`, and invoke
`ocx-mirror` directly — never `ocx run -- ocx-mirror`, which pins
`OCX_BINARY_PIN` to the bootstrap `ocx` and false-reds the nested push.

## The binaries claim

`cosign/metadata.json` declares `binaries: ["cosign"]` by hand, and
`mirror-base.yml` sets `bin_scan: "off"` — forced, not preferred. Every asset
is a raw binary, so it lands at the bundle content root and `PATH` is a bare
`${installPath}`; the scan only inspects an interface-visible
`${installPath}/<dir>` entry, so with no subdirectory to point at, `auto` and
`verify` both fail spec load at exit 65 rather than offer a hollow check.

The hand list is **load-bearing beyond documentation** here: GitHub serves raw
release assets with mode `0644` (measured on all 15 downloaded assets), and
`prepare` chmods `0755` exactly the names `metadata.json` declares. An
undeclared binary would ship non-executable, and `bin_scan: auto` could not
rescue it — the scan only reports candidates it finds *already* executable.

`asset_type.name: cosign` renames each platform's asset to the bare tool name.
The upstream Windows asset is already `cosign-windows-amd64.exe`, so the `.exe`
suffix survives into the bundle and no per-platform override is needed —
`asset_type: binary` preserves a suffix but never *synthesises* one. Verified
rather than assumed, with a runner-less `pipeline prepare` against a
windows-only probe spec followed by `tar tvf`.

## The smoke test

`cosign/tests/smoke.star` runs a complete asymmetric-key round trip in the test
scratch sandbox and asserts what cosign *computed*, never what it printed.

**It deliberately does not sign a blob.** The obvious smoke for a signing tool
is `sign-blob` → `verify-blob`, and in cosign v3 that is not available offline.
Measured on all three versions under `docker run --network none`: `sign-blob`
without `--bundle` refuses (`must specify --bundle with --new-bundle-format`),
with `--bundle` it fetches the signing config from `tuf-repo-cdn.sigstore.dev`,
and with `--use-signing-config=false` it still POSTs to
`rekor.sigstore.dev/api/v1/log/entries`. v3 removed v2's `--tlog-upload=false`,
so every signing path reaches the network — a smoke built on it would test
Sigstore's uptime on every leg. It would also be **unstable across this very
range**: `verify-blob --signature` exists in 3.0.6 and was removed in 3.1.1, so
the flag pair the two halves need does not span the mirrored versions.

What is hermetic is the key half, and it is the half that exercises real
cryptography:

- `cosign version` matches a version **shape** regex — the digits are the
  contract, the banner is not, and cosign proves the point inside this range:
  the tagline lost its trailing full stop between 3.1.1 and 3.1.2.
- The same output carries `Platform: linux/amd64` in Go's GOOS/GOARCH spelling,
  which is compared against the platform the bundle was **built for**. A
  mis-mapped `assets:` key — arm64 bytes under the amd64 platform — resolves
  fine, tests fine on a native runner and is invisible to the platform gate,
  but cannot survive that line.
- `cosign generate-key-pair` must write a **scrypt-encrypted** private key and
  an SPKI public key; the PEM headers are structural output, and a build that
  silently wrote an unencrypted private key would pass an exit-code-only check.
- `cosign public-key --key cosign.key` decrypts that private key, recovers the
  EC scalar, re-derives the public point and must produce output
  **byte-identical** to the `cosign.pub` written at keygen time.
- Two negative controls. The **wrong passphrase** must fail in the decryption
  stage (exit 1, "decryption failed") — without it, the round trip above is
  satisfiable by a tool that cached the public key and echoed it back. And a
  **malformed PEM** must be rejected at decode ("invalid pem block"), the one
  class of negative assertion that is portable across every container leg
  because it reaches no socket and no host tool.

Every assertion was replayed under `--network none` in stock `alpine:3.20`
against 3.0.6, 3.1.1 and 3.1.2 before being written.

## Required secrets

| Secret | Use |
|--------|-----|
| `OCX_ANNOUNCE_TOKEN` | opens the index pull request from the `ocx-contrib/index` fork |
| `OCX_MIRROR_DISCORD_HOOK` | notify-stage Discord webhook URL |

(Inherited from the `ocx-contrib` org with visibility ALL. GHCR pushes use the
run's own `GITHUB_TOKEN` — no registry secret needed.)

## License

Apache-2.0 — see [`LICENSE`](LICENSE). Upstream assets are out of scope; the
package's redistribution license is recorded in [`NOTICE.md`](NOTICE.md). The
logo is upstream's own mark, re-encoded for catalog identification only.
