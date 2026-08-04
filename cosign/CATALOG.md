---
title: cosign
description: Sign and verify container images, blobs and attestations — keyless with Sigstore, or with your own keys
keywords: cosign,sigstore,signing,signature,verification,supply-chain,slsa,attestation,sbom,provenance,oci,container,keyless,rekor,fulcio,go,cli
---

# cosign

[cosign](https://github.com/sigstore/cosign) is the signing and verification
tool of the [Sigstore](https://www.sigstore.dev) project. It signs container
images, arbitrary files and attestations, and verifies them again — either
**keyless**, using a short-lived certificate bound to an OIDC identity and
recorded in the public [Rekor](https://github.com/sigstore/rekor) transparency
log, or with a **key pair** you hold yourself (on disk, in a hardware token, or
in a cloud KMS). Signatures for an image are stored alongside it in the same
OCI registry, so nothing new has to be hosted.

## What's included

- **cosign** — the binary. `cosign generate-key-pair` creates a passphrase-
  protected key pair, `cosign sign` / `cosign verify` handle container images,
  `cosign sign-blob` / `cosign verify-blob` handle files, `cosign attest` /
  `cosign verify-attestation` handle in-toto attestations and SBOMs, and
  `cosign tree` shows every signature, attestation and SBOM attached to an
  image.

## Quick start

```sh
# Key-based: generate a pair, then sign and verify an image
cosign generate-key-pair
cosign sign --key cosign.key ghcr.io/example/app:1.0.0
cosign verify --key cosign.pub ghcr.io/example/app:1.0.0
```

```sh
# Keyless: no long-lived key at all — identity comes from an OIDC login
# and the signature is logged to the public transparency log
cosign sign ghcr.io/example/app:1.0.0
cosign verify ghcr.io/example/app:1.0.0 \
  --certificate-identity you@example.com \
  --certificate-oidc-issuer https://accounts.google.com
```

```sh
# Verify a file signed with a Sigstore bundle
cosign verify-blob --bundle artifact.sigstore.json --key cosign.pub ./artifact.tar.gz
```

Keyless signing and any verification that consults the transparency log need
network access to the Sigstore public good instances. Key generation and
key-pair operations are entirely local.

## Version note

This package mirrors the **v3.x** line. cosign maintains v2.x in parallel as an
LTS branch; it is not carried here.

## Install with ocx

```sh
ocx install ocx.sh/sigstore/cosign
```

```sh
# or pin a specific version
ocx install ocx.sh/sigstore/cosign:3.1.2
```

## Links

- [cosign on GitHub](https://github.com/sigstore/cosign)
- [Sigstore documentation](https://docs.sigstore.dev/)
- [cosign command reference](https://github.com/sigstore/cosign/blob/main/doc/cosign.md)
