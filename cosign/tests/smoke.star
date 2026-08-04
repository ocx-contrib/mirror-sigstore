# cosign/tests/smoke.star — stable across upstream cosign v3.x releases.
#
# Asserts the contract (exit codes, version SHAPE, the platform cosign says it
# was built for, and a real asymmetric-key round trip cosign COMPUTED), never
# help/version prose.
#
# WHY NOTHING SIGNS A BLOB. The obvious smoke for a signing tool is
# sign-blob → verify-blob, and in cosign v3 it is NOT AVAILABLE OFFLINE.
# Measured on all three in-range versions inside `docker run --network none`:
#
#   sign-blob --key cosign.key --yes blob.txt
#     → "must specify --bundle with --new-bundle-format"       (v3.1.x)
#   sign-blob --key cosign.key --bundle b.json --yes blob.txt
#     → "error getting signing config from TUF: … tuf-repo-cdn.sigstore.dev"
#   sign-blob --key … --use-signing-config=false --bundle …
#     → "signing bundle: Post https://rekor.sigstore.dev/api/v1/log/entries"
#
# v3 removed v2's `--tlog-upload=false`, so every signing path reaches the
# public Rekor log or the TUF root. A smoke that needed those would test
# sigstore's uptime on every leg. It would also be UNSTABLE across this very
# range: `verify-blob --signature` exists in 3.0.6 and was REMOVED in 3.1.1,
# so the flag pair the two halves need does not span the mirrored versions.
#
# What IS hermetic is the KEY half, and it is the half that actually exercises
# cryptography rather than a network round trip: keygen, scrypt-wrapping the
# private key, decrypting it again, and re-deriving the public point from it.
# Every assertion below was replayed under `--network none` in stock
# `alpine:3.20` against 3.0.6, 3.1.1 and 3.1.2 before being written here.

COSIGN = "cosign.exe" if ocx.target_platform.os == ocx.os.Windows else "cosign"

# Non-empty on purpose. cosign prompts interactively for a key passphrase when
# COSIGN_PASSWORD is unset, and an empty value would rest on `env=` passing a
# set-but-empty var through unchanged — a distinction not worth depending on
# when any string works. It is also what makes the wrong-password negative
# control below a real discriminator rather than "empty vs unset".
PW = "ocx-smoke-pw"

# cosign persists TUF state under $HOME on the paths that touch the network.
# None of the verbs below does, but a container leg where HOME is unset or
# unwritable is exactly where that assumption would be discovered the
# expensive way, so it is pointed at the write-enabled scratch sandbox.
ENV = {"COSIGN_PASSWORD": PW, "HOME": ocx.scratch_root}

# ─── Tier 1 + 2: liveness on the composed PATH + version SHAPE ──────────────
#
# The digits are the contract; the banner around them is not — and cosign
# proves the point INSIDE this range: the tagline lost its trailing full stop
# between 3.1.1 and 3.1.2 ("…in an OCI registry." → "…in an OCI registry"), and
# every release prints six lines of ASCII art above it. So: shape only. The
# tag carries a "v" prefix that the version does not, so the regex is
# deliberately unanchored rather than `^`-anchored.
r_version = ocx.run(COSIGN, "version", env = ENV)
expect.ok(r_version)
expect.matches(r_version.stdout, r"\d+\.\d+\.\d+")

# ─── Tier 2b: platform identity — free, and the one bug the gate can't see ──
#
# `cosign version` prints `Platform:  linux/amd64` using Go's GOOS/GOARCH,
# which are the same spellings as the OCI platform keys. Comparing it against
# the platform this bundle was BUILT for proves the asset regex shipped the
# right artifact into the right bundle — a mis-mapped `assets:` key (arm64
# bytes under the amd64 platform) resolves fine, tests fine on a native runner,
# and is invisible to the platform gate, but cannot survive this line.
# On darwin/amd64 the amd64 slice runs under Rosetta 2 on an arm64 macos-14
# runner; GOARCH is fixed at compile time, so it still reports `darwin/amd64`.
expect.contains(
    r_version.stdout,
    str(ocx.target_platform.os) + "/" + str(ocx.target_platform.arch),
)

# ─── Tier 3a: generate a real key pair ──────────────────────────────────────
#
# Writes cosign.key + cosign.pub into the scratch root (cwd defaults there, so
# every path below stays relative and is correct on Windows too, with no
# separator juggling).
r_keygen = ocx.run(COSIGN, "generate-key-pair", env = ENV)
expect.ok(r_keygen)

# The PEM headers are cosign's own structural output, not prose: the private
# key must come back scrypt-ENCRYPTED (that is what the passphrase is for) and
# the public half must be a standard SPKI block. A build that silently wrote an
# unencrypted private key would pass an exit-code-only check.
priv = ocx.read_file("cosign.key")
pub = ocx.read_file("cosign.pub")
expect.contains(priv, "-----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----")
expect.contains(pub, "-----BEGIN PUBLIC KEY-----")

# ─── Tier 3b: the round trip — cosign RE-DERIVES the public key ─────────────
#
# `public-key` decrypts the scrypt-wrapped private key with the passphrase,
# recovers the EC private scalar, multiplies out the public point and re-encodes
# it. The result must be BYTE-IDENTICAL to the cosign.pub written at keygen
# time. This is the functional assertion: it fails on a truncated binary, on a
# broken crypto backend, and on any artifact that is not really cosign — while
# depending on no network, no registry and no clock.
r_pub = ocx.run(COSIGN, "public-key", "--key", "cosign.key", env = ENV)
expect.ok(r_pub)
expect.eq(r_pub.stdout.strip(), pub.strip())

# ─── Tier 3c: NEGATIVE CONTROL 1 — the passphrase is really checked ─────────
#
# Without this, Tier 3b is satisfiable by a tool that cached the public key at
# keygen and echoed it back. Feeding the WRONG passphrase must fail, and fail
# in the decryption stage: cosign exits 1 with "decryption failed" (measured on
# all three versions). Exit 1 is a POSITIVE code — Go's os.Exit(1) — so it
# needs no platform branch, unlike a tool returning -1 (255 on unix, -1 on
# Windows).
r_wrongpw = ocx.run(
    COSIGN,
    "public-key",
    "--key",
    "cosign.key",
    env = {"COSIGN_PASSWORD": "not-the-passphrase", "HOME": ocx.scratch_root},
)
expect.eq(r_wrongpw.exit_code, 1)
expect.contains(r_wrongpw.stderr, "decrypt")

# ─── Tier 3d: NEGATIVE CONTROL 2 — malformed input is rejected at decode ────
#
# A decode-stage input rejection is the one class of negative assertion that is
# portable across every container leg: it reaches no provider, no socket and no
# host tool. cosign answers "invalid pem block", exit 1, on all three versions.
ocx.write_file("junk.pem", "this is not a key\n")
r_junk = ocx.run(COSIGN, "public-key", "--key", "junk.pem", env = ENV)
expect.eq(r_junk.exit_code, 1)
expect.contains(r_junk.stderr, "pem")

# No Tier 4: metadata.json declares PATH only (proven by the Tier 1 liveness
# call resolving `cosign` off the composed PATH).
