IMPORTANT: Ensure you've thoroughly reviewed the [AGENTS.md](AGENTS.md) file before beginning any work.

# llama.cpp for SA8650P (Hexagon NPU / HTP)

This is a local working copy of upstream llama.cpp (commit `635cdd5fc`, 2026-07-17), used to build the ggml-hexagon backend for the SA8650P ADAS board (DSP v73, glibc 2.35). Target: run LLM inference on the cDSP/HTP NPU.

# Build

## Toolchain (custom, NOT the official CMake preset)

The official `arm64-linux-snapdragon-release` preset uses the `ghcr.io/snapdragon-toolchain/arm64-linux:v0.1` docker image, whose aarch64 sysroot is Debian 13 / glibc 2.41. The SA8650P board runs glibc 2.35, so binaries from that image fail with `GLIBC_2.38 not found`.

Use the custom toolchain instead:
- **Host-side ARM64**: `aarch64-oe-linux-gcc` 11.4.0 from the `byuns-rust-toolchain:local` docker image (base image `byuns_g300_8650p_linux-v73_2.35`, OE-Linux cortex-a78c sysroot, glibc 2.35). Ships a complete GCC toolchain (crt, libgcc, libstdc++ headers) - no clang/sysroot stitching needed.
- **DSP-side htp skels**: `hexagon-clang` from `hexagon-sdk-6.6/tools/HEXAGON_Tools/19.0.07`. SDK 6.6 is required (5.5 does NOT work - see Known Issues).
- Toolchain file: `cmake/arm64-linux-oe-sysroot.cmake` (points clang/gcc at the OE sysroot).
- Build script: `scripts/snapdragon/build-linux-oe.sh` (mounts hexagon-sdk-6.6 + tools into the byuns image, uses the custom toolchain, does NOT use CMakePresets).

Artifacts land in `pkg-snapdragon-oe/`.

## Why not the local Hexagon SDK 5.5 / Tools 8.7

`hexagonsdk5.5.5` + `hexagon8.7` are too old for current ggml-hexagon source:
1. `qaic` layout differs: 5.5 uses `qaic/Ubuntu*/qaic`, current code expects `qaic/bin/qaic` (only in 6.6).
2. `MAX_DOMAIN_NAMELEN` undefined in 5.5's `remote.h` (defined in 6.6).
3. Hexagon Tools 8.7.06 vs 19.0.07 - HVX 64B deprecated `-Werror` errors on old tools.

Use `hexagon-sdk-6.6` (6.6.0.0 + Tools 19.0.07) which matches the current ggml-hexagon code.

# Deploy to board

```bash
# host
scp -P 2222 pkg-snapdragon-oe/lib/<file> bin.feng@root@<UUID>@bastion-bench.momenta.works:/winterfell/pkg-snapdragon-oe/lib/

# board (UUID rotates per session - check bastion portal for the live one)
cd /winterfell/pkg-snapdragon-oe
export LD_LIBRARY_PATH=./lib
export ADSP_LIBRARY_PATH=./lib
export CDSP_LIBRARY_PATH=./lib        # REQUIRED - cDSP searches skel here, NOT ADSP_LIBRARY_PATH
./bin/llama-cli -m <model.gguf> --device HTP0 -ngl 99 -p "hello"
```

The board's cDSP uses a non-standard fastrpc backend (`libkiumd.so` + `fastrpc-rm` daemon + `/dev/kiumd` -> VFIO -> cDSP). There is no `/dev/cdsp*` or `/dev/fastrpc*`. Despite cDSP being under VFIO, the fastrpc channel works (QNN `qnn-net-run` runs on this board).

# Known Issues (the full journey, resolved)

The path to a working HTP skel required fixing four independent layers, in order. Each failure masked the next.

## 1. GLIBC version mismatch (host sysroot too new)

- Symptom: `./bin/llama-cli: /lib/libc.so.6: version GLIBC_2.38 not found`
- Root cause: official snapdragon docker image (Debian 13) has glibc 2.41; board has 2.35.
- Fix: use the byuns-rust-toolchain image (OE glibc 2.35 sysroot) via `build-linux-oe.sh`. See Build above.

## 2. Missing SWIV segment (cDSP ELF verification)

- Symptom (after #1): `dsp dlopen error: ::ELF verification: section header for CRC segment not found`, `failed to open session : error 0x80000406`.
- Root cause: cDSP fusa firmware dlopen-rejects any fastrpc `*_skel.so` that lacks a SWIV (Secure World Integrity Verification) segment. llama.cpp's `htp/CMakeLists.txt` builds the skel with bare `hexagon-link` and never injects SWIV. QNN/Calculator skels have it (Qualcomm's internal build adds it); `hexagon-link` does not auto-add it; `elfsigner.py`/sectools does NOT generate it (zero hits for SWIV/0x535749/crc across sectools).
- SWIV segment structure (16 bytes, confirmed on QNN 2.35/2.42 + Calculator skels):
  - `[0:4]` magic `0x56495753` ("SWIV", LE)
  - `[4:8]` CRC32 (LE)
  - `[8:16]` zeros
  - section header: `sh_type=0xd3574956`, `sh_name=0` (unnamed), `sh_flags=0`, `sh_addr=0`, `sh_size=0x10`, `sh_addralign=0`. Data at end of file, outside any LOAD segment.
- CRC32 algorithm (reverse-engineered, double-sample verified):
  - `zlib.crc32` over the concatenation of every `PT_LOAD` segment's file content, each **padded with zeros to `p_memsz`** (covers .bss), in program-header order.
  - IMPORTANT: the ELF header lives inside LOAD0 (LOAD0 starts at offset 0), so the CRC covers `e_shoff`/`e_shnum`. The CRC must be computed AFTER finalizing the header (injector lays out SWIV data + relocated SHT, updates header, THEN computes CRC and back-fills it). The stored CRC value changes after injection (because e_shoff changed); cDSP only checks recomputed == stored (self-consistency), not a fixed value.
  - Verification: Calculator_skel (FileSiz==MemSiz) -> 0xb1e4d77d matches; QNN skel (MemSiz>FileSiz, has .bss) -> 0xf1ebb04a matches only with MemSiz zero-padding (FileSiz gives 0x3708e739, wrong).
- Fix: `scripts/snapdragon/add_swiv.py` (pure Python, ~50 lines) appends the SWIV section + relocates the SHT + back-fills CRC. Run after every skel build:
  ```bash
  python3 scripts/snapdragon/add_swiv.py pkg-snapdragon-oe/lib/libggml-htp-v73.so /tmp/skel.swiv
  cp /tmp/skel.swiv pkg-snapdragon-oe/lib/libggml-htp-v73.so
  ```
  Verify self-consistency with the snippet in `add_swiv.py` header comment.

## 3. Undefined `compute_resource_attr_init_v2` symbol (cDSP lacks _v2 API)

- Symptom (after #2): `dsp dlopen error: ::undefined symbol #113 compute_resource_attr_init_v2 in ./libggml-htp-v73.so`
- Root cause: `HAP_compute_res.h` (SDK 6.6) declares `compute_resource_attr_init_v2` as a weak symbol, and the `static inline HAP_compute_res_attr_init()` references it. The skel ends up with `compute_resource_attr_init_v2` as a WEAK UND dynsym entry. The SA8650P fusa cDSP firmware only provides the OLD version `compute_resource_attr_init` (no `_v2`), and its dlopen does NOT silently NULL-resolve weak UND symbols for this particular symbol - it reports undefined.
- Key contrast: QNN skel (runs) does NOT reference `init_v2` at all. Both QNN and ggml skels reference `set_vtcm_param_v2`/`get_vtcm_ptr_v2`/`HAP_debug_v2` (cDSP silently NULL-resolves those) - ONLY `init_v2` needs handling.
- Fix: `ggml/src/ggml-hexagon/htp/v2_shim.c` defines `compute_resource_attr_init_v2` as a **weak defined** function returning `0x80000404` (HAP_COMPUTE_RES_NOT_SUPPORTED). This turns the dynsym entry from UND to DEF (cDSP stops reporting undefined), and at runtime the inline `HAP_compute_res_attr_init()` calls the shim -> returns nonzero -> falls back to the old `compute_resource_attr_init` (which cDSP provides). The shim is added to `htp/CMakeLists.txt` `add_library(... SHARED ...)` source list.
  ```c
  // v2_shim.c
  #include <stddef.h>
  int __attribute__((weak)) compute_resource_attr_init_v2(void * attr, unsigned int size, unsigned int version) {
      (void)attr; (void)size; (void)version;
      return 0x80000404;
  }
  ```
  IMPORTANT: only shim `init_v2`. Do NOT shim `set_vtcm_param_v2`/`get_vtcm_ptr_v2` - those inline functions have NO fallback path, so a shim (returning 0 with vtcm_ptr=NULL) would make VTCM allocation silently fail and crash later. `HAP_debug_v2` also needs no shim (cDSP resolves it).
  Verify: `hexagon-llvm-readelf --dyn-syms skel.so | grep init_v2` should show `FUNC WEAK DEFAULT <N>` (defined), not `UND`.

## 4. NEEDED dependency `libc.so`/`libgcc.so` missing on cDSP

- Symptom (after #3): `failed to open session : error 0x2`, journal `dsp dlopen error` gone but `fastrpc init failed`.
- Root cause: ggml skel `NEEDED` = `libc.so` + `libgcc.so` (Hexagon C runtime). cDSP `/vendor/dsp/cdsp/` only ships `libc++.so.1` (QNN skel depends on `libc++.so.1`+`libc++abi.so.1`, which cDSP has). cDSP can't resolve `libc.so`/`libgcc.so` -> dlopen of the skel fails with AEE_EFAILED (0x2).
- Fix: copy hexagon v73 runtime libs to the skel's directory (which `CDSP_LIBRARY_PATH` points at):
  ```bash
  # from hexagon-sdk-6.6
  scp tools/HEXAGON_Tools/19.0.07/Tools/target/hexagon/lib/v73/G0/pic/libc.so  board:.../lib/
  scp tools/HEXAGON_Tools/19.0.07/Tools/target/hexagon/lib/v73/G0/pic/libgcc.so board:.../lib/
  ```
  These are Hexagon ELF (Machine: Qualcomm Hexagon), no SWIV needed (only `*_skel` libs need SWIV), no transitive deps.

## 5. Loading the wrong skel copy (CDSP_LIBRARY_PATH not set)

- Symptom: after all fixes, STILL `undefined symbol init_v2` - because cDSP loaded a stale skel from a different path.
- Root cause: cDSP searches for `file:///libggml-htp-v73.so` via `CDSP_LIBRARY_PATH` (NOT `ADSP_LIBRARY_PATH`/`LD_LIBRARY_PATH`). The board had multiple stale copies: `/usr/share/fastrpc/`, `/ota/geniex-pkg/llama_cpp/`, `/winterfell/pkg-snapdragon/`. llama-cli without `CDSP_LIBRARY_PATH` loaded the old `/usr/share/fastrpc/` copy.
- Fix: `export CDSP_LIBRARY_PATH=./lib` (or the absolute path). Also deleted `/usr/share/fastrpc/libggml-htp-v73.so` to avoid ambiguity. Always verify with `md5sum` on the board vs host.

## 6. fastrpc unsigned PD `open_shell` failure (NOT a skel problem)

- Symptom (after #5): `failed to open session : error 0x2`, journal: `[load_fastrpc_shell] :error: 2`, `[fastrpc_pd_infra_init] Error 2`, `remote_handle64_open fastrpc init failed returning error 2`. NO `dsp dlopen error` - the skel itself is fine now.
- This is a fastrpc unsigned-PD infrastructure failure at `open_shell`, BEFORE skel dlopen. Happens when the cDSP PD state is stale (from prior failed dlopens) or the fastrpc-rm daemon / kiumd channel isn't set up the way geniex sets it up.
- Status: NOT yet resolved for llama-cli. GenieX (`/home/binfeng/work/qual/GenieX`) runs to interactive stage on the same board - it sets `CDSP_LIBRARY_PATH` with multiple paths (`/ota/geniex-pkg/llama_cpp;/vendor/dsp/cdsp;/firmware/image`) and runs the `fastrpc-rm` daemon. Need to replicate geniex's env to get llama-cli past this.

# GenieX as the working reference

`/home/binfeng/work/qual/GenieX` has a working llama.cpp (older commit `be4a6a63e`, 2026-06-23) that reaches interactive stage on SA8650P. Differences vs this project:
- GenieX htp CMakeLists builds only 5 sources (`main.c htp_iface_skel.c worker-pool.c hex-dma.c v2_shim.c`); this project builds 28 (new version split ops into separate files + added `hmx-queue.c`). New version likely references extra symbols (e.g. `dspqueue_peek`) the cDSP may not have.
- GenieX's skel (`/ota/geniex-pkg/llama_cpp/libggml-htp-v73.so`, md5 `be4eb82b`) has SWIV + v2_shim and runs. Its `v2_shim.c` is identical to this project's.
- Path forward to get this project's NPU working: either (a) replicate geniex's full env for llama-cli to pass #6, or (b) temporarily use geniex's skel as a stepping stone, or (c) fix this project's skel deps to match what cDSP offers.

# CPU-only run (no NPU)

CPU backend (`libggml-cpu.so`, pure ARM64, depends on libstdc++/libm/libgcc_s which the board has) is independent of the hexagon skel. To run CPU-only and skip the hexagon backend entirely:
```bash
cd /winterfell/pkg-snapdragon-oe
# disable hexagon backend so it doesn't try to open a session during backend registration
mv lib/libggml-hexagon.so lib/libggml-hexagon.so.disabled
mv lib/libggml-hexagon.so.0 lib/libggml-hexagon.so.0.disabled 2>/dev/null
mv lib/libggml-hexagon.so.0.16.0 lib/libggml-hexagon.so.0.16.0.disabled 2>/dev/null
# OR: export GGML_HEXAGON_NDEV=0   (hexagon reports 0 devices, skips session creation)
export LD_LIBRARY_PATH=./lib
./bin/llama-cli -m <model.gguf> -ngl 0 -t 6 -p "hello"
```
Note: the hexagon backend opens its cDSP session EAGERLY at registration time (`ggml_hexagon_registry` ctor loops `for i<opt_ndev: new ggml_hexagon_session` -> `htp_iface_open`), so any session failure aborts before CPU inference starts. Moving the .so out of the search path prevents registration entirely.

# Stepwise NPU offload (once #6 is resolved)

1. Confirm CPU-only runs (`-ngl 0`).
2. `--device HTP0 -ngl 1` (1 layer to NPU), check which op crashes.
3. Increase `-ngl` (10, 50, 99) incrementally; inspect the failing op via `GGML_HEXAGON_VERBOSE=1`.
4. Use `test-backend-ops -b HTP0 -o <OP>` to test individual ops on HTP.
