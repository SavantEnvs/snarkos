#!/usr/bin/env bash
#
# snarkOS/mayhem/build.sh — build cargo-fuzz libFuzzer targets + file-input _no_inst reproducers.
#
# At UPSTREAM, snarkOS still ships its own fuzz/ crate (the harness mayhemheroes's run fuzzed);
# mayhem/fuzz/ here is a copy of it, trimmed to the backport's one target, depending on the real
# snarkos-environment crate like the original. cargo-fuzz builds the libFuzzer binary; a plain
# `cargo build --release` on the same crate produces the _no_inst file-input reproducer
# (libfuzzer-sys run-once driver, no libFuzzer runtime).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }
TRIPLE="x86_64-unknown-linux-gnu"

# ASan on by default; an explicitly EMPTY $SANITIZER_FLAGS disables it (build contract parity —
# $SANITIZER_FLAGS itself is a set of clang flags rustc can't consume directly, so translate its
# on/off intent instead of passing it through verbatim).
RUST_SAN="-Zsanitizer=address"
[ -z "${SANITIZER_FLAGS+x}" ] || [ -n "${SANITIZER_FLAGS}" ] || RUST_SAN=""
# DWARF <= 3 debug info for triage (SPEC §6.2 item 10) — threaded via RUST_DEBUG_FLAGS.
RUST_DEBUG_FLAGS="${RUST_DEBUG_FLAGS:--Cdebuginfo=1 -Zdwarf-version=3}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing $RUST_SAN $RUST_DEBUG_FLAGS -Cforce-frame-pointers"
# libfuzzer-sys's build.rs, by default, compiles libFuzzer's own C++ sources from source via the
# `cc` crate at build time — that build ignores CFLAGS/CXXFLAGS (cc::Build's own flags win) and
# links in DWARF-5 CUs from the base image's clang, which -Zdwarf-version=3 (a rustc-only flag)
# never touches. Point it at the base's prebuilt libFuzzer runtime instead (the same one the C/C++
# side gets via $LIB_FUZZING_ENGINE) — it ships with NO debug info at all, so it contributes zero
# DWARF-5 CUs, and libfuzzer-sys skips its own from-source compile entirely.
export CUSTOM_LIBFUZZER_PATH=/usr/lib/llvm-19/lib/clang/19/lib/linux/libclang_rt.fuzzer-x86_64.a

# rustc's prebuilt sanitizer runtimes (compiler-rt) ship DWARF-5 CUs (e.g. asan_allocator.cpp,
# asan_errors.cpp, ...) — strip their debug info BEFORE linking, not after: the linker COPIES the
# relevant debug sections into the final binary at link time, so stripping the source .a
# afterward does nothing for a binary already linked against it. Idempotent: stripping an
# already-stripped archive is a no-op.
find "$RUSTUP_HOME"/toolchains/*/lib/rustlib/"$TRIPLE"/lib \
  -name 'librustc-*_rt.*.a' -exec objcopy --strip-debug {} \; 2>/dev/null || true

echo "=== cargo +nightly-2025-09-05 fuzz build (ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo +nightly-2025-09-05 fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "=== cargo +nightly-2025-09-05 build _no_inst reproducers (no libFuzzer runtime) ==="
export RUSTFLAGS="--cfg fuzzing $RUST_DEBUG_FLAGS -Clink-dead-code -Cdebug-assertions -Ccodegen-units=1"
cargo +nightly-2025-09-05 build --release --manifest-path "$FUZZ_DIR/Cargo.toml" --jobs "$MAYHEM_JOBS"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$SRC/$FUZZ_DIR/target/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected _no_inst binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/${t}_no_inst"
  echo "built /mayhem/${t}_no_inst"
done

echo "build.sh complete:"
ls -la /mayhem/deserialization /mayhem/deserialization_no_inst

# The root Cargo.lock pins ahash 0.7.6 (indexmap -> hashbrown's default hasher): its `stdsimd`
# feature gate is self-enabled on this crate version and no longer compiles under a current
# nightly (`feature(stdsimd)` was stabilized/renamed upstream). Re-pin it to 0.7.8 — the same
# semver-compatible release the independent mayhem/fuzz workspace resolves above, already cached
# in the registry by that step — without touching the tracked root Cargo.lock.
cargo update -p ahash --precise 0.7.8 --offline 2>/dev/null || cargo update -p ahash --precise 0.7.8

echo "=== precompile workspace lib tests (hermetic subset) ==="
# snarkos-network/-storage (rocksdb via librocksdb-sys/bindgen) don't build: bindgen 0.59 emits an
# enum variant name libclang 19 rejects as an identifier (old bindgen x current libclang). Neither
# crate is on the deserialization fuzz target's dependency path (snarkos-environment doesn't need
# them); test the rest of the hermetic workspace instead.
RUSTFLAGS="" cargo test --workspace --lib --no-run --no-fail-fast \
  --exclude snarkos --exclude snarkos-rpc --exclude snarkos-crawler \
  --exclude snarkos-network --exclude snarkos-storage \
  --exclude snarkos-integration --exclude snarkos-synthetic-node \
  --jobs "$MAYHEM_JOBS" -- --skip test_block_locators_serde_json
