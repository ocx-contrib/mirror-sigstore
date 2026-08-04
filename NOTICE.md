# NOTICE

This repository packages and redistributes upstream software published by the
[Sigstore](https://www.sigstore.dev) project. The Apache-2.0 license in
[`LICENSE`](LICENSE) covers the OCX pipeline files authored here. It does
**not** cover any upstream-derived asset — the redistributed bytes carry their
own license, recorded below.

The package logo is upstream's own mark
([`sigstore_cosign-icon-color.svg`](https://github.com/sigstore/community/blob/main/artwork/cosign/icons/color/sigstore_cosign-icon-color.svg)
from the Sigstore community artwork repository), re-encoded to 512×512 for
catalog identification only. No endorsement is implied, and no trademark claim
is made.

| Package | GHCR path | Upstream SPDX |
|---|---|---|
| `cosign` | `ghcr.io/ocx-contrib/sigstore/cosign` | `Apache-2.0` |

---

## `cosign`

Upstream: <https://github.com/sigstore/cosign>
Published to `ghcr.io/ocx-contrib/sigstore/cosign`.

| Component | SPDX | Holder |
|---|---|---|
| cosign | **Apache-2.0** | Copyright 2021 The Sigstore Authors |

Verified at the Phase 1.5 license gate:

```
$ gh api repos/sigstore/cosign/license --jq '{spdx: .license.spdx_id, path: .path}'
{"path":"LICENSE","spdx":"Apache-2.0"}
```

The `LICENSE` blob was re-read directly rather than trusted from the API
classifier: it is the stock 201-line Apache License 2.0 text with the unfilled
`Copyright [yyyy] [name of copyright owner]` appendix, no added clauses and no
modifications. The copyright holder is taken from the source headers
(`cmd/cosign/main.go`: `// Copyright 2021 The Sigstore Authors.`).

Apache-2.0 is permissive and grants redistribution of the compiled binary,
subject to its notice-retention and change-statement conditions (§4). Upstream's
release assets are **raw uncompressed binaries** — a single file per platform
with no archive around it and therefore no `LICENSE` or `NOTICE` file travelling
alongside — so the notice is retained here instead. The canonical text is
<https://github.com/sigstore/cosign/blob/main/LICENSE>, and every published
manifest carries an `org.opencontainers.image.source` annotation pointing at
this repository alongside `org.opencontainers.image.licenses: Apache-2.0`.

The published binaries are statically linked Go builds that vendor third-party
modules under permissive licenses, enumerated in the `go.mod` / `go.sum` of the
tagged upstream source for each mirrored version.

No modifications are made to any upstream artifact in this repository; they are
republished byte-for-byte inside an OCX bundle. Two transformations are applied
to the container, never to the bytes, and both are recorded here as the
Apache-2.0 §4(b) change statement:

- **The file is renamed** from its platform-qualified upstream name
  (`cosign-linux-amd64`, `cosign-windows-amd64.exe`) to `cosign` /
  `cosign.exe`, so that one command name works on every platform.
- **The executable mode bit is set.** GitHub serves raw release assets as
  `0644`; `prepare` chmods the declared binary to `0755` so it can be run at
  all.
