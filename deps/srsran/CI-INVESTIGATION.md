# srsRAN CI Investigation

## Status

The Aether OnRamp srsRAN workflow is reliable with the
`aetherproject/srsran-{gnb,ue}:rel-0.4.0` image pair. Newer image pairs tested
so far do not work on GitHub-hosted runners.

The upstream OnRamp fix is tracked in
[opennetworkinglab/aether-onramp#221](https://github.com/opennetworkinglab/aether-onramp/pull/221).

## Test Matrix

| gNB image | UE image | Result | Evidence |
| --- | --- | --- | --- |
| `rel-0.4.0` | `rel-0.4.0` | Pass | [run 27037970727](https://github.com/andybavier/aether-onramp/actions/runs/27037970727) |
| `rel-0.7.0` | `rel-0.7.0` | Fail: UE never attaches | [run 27037171597](https://github.com/andybavier/aether-onramp/actions/runs/27037171597) |
| `rel-0.5.0` | `rel-0.5.0` | Fail: UE exits with `SIGILL` | [run 27039123397](https://github.com/andybavier/aether-onramp/actions/runs/27039123397) |
| `rel-0.5.0` | `rel-0.4.0` | Fail: UE never attaches | [run 27039664293](https://github.com/andybavier/aether-onramp/actions/runs/27039664293) |
| `rel-0.5.0` with single lower-PHY profile | `rel-0.4.0` | Pending | Test branch |

## Timeline

- February 24, 2026: the last known successful CI run used the `rel-0.4.0`
  gNB and UE images.
- April 2026: OnRamp moved both images to `rel-0.7.0`. Subsequent CI runs
  failed because the UE tunnel interface was never created.
- June 5, 2026: increasing the UE startup wait from 10 seconds to 90 seconds
  confirmed that this was not a timing race.
- June 5, 2026: restoring both images to `rel-0.4.0` made CI pass.
- June 5, 2026: testing `rel-0.5.0` exposed two separate failures described
  below.

## Confirmed Findings

### `rel-0.7.0` pair

The gNB starts, connects to the AMF, and activates its cell. The UE starts its
ZMQ radio, initializes the PHY, and stops at:

```text
Waiting PHY to initialize ... done!
Attaching UE...
```

No PRACH or UE activity appears in the gNB log. The `tun_srsue` interface is
not created, even after 18 checks over 90 seconds.

### `rel-0.5.0` UE run

The all-`rel-0.5.0` run observed the UE exiting immediately:

```text
./startup.sh: line 5: 8 Illegal instruction (core dumped) srsue ue_zmq.conf
```

The `rel-0.5.0` image metadata identifies:

- srsRAN-docker commit `d08e759ca38f3544433bf86d61f05ee0f38de4e1`
- srsRAN_4G ref `release_23_11`
- srsRAN_4G commit `eea87b1d893ae58e0b08bc381730c502024ae71f`

Static inspection after downloading the images found that `rel-0.4.0` and
`rel-0.7.0` contain the same srsRAN_4G source commit. Their `srsue`
executables and dynamic RF libraries differ by only 30 build-metadata bytes
and have identical vector-instruction profiles. Both contain AVX/AVX2 code
selected by srsRAN_4G's automatic ISA detection.

The `SIGILL` is therefore not established as a code change introduced in
`rel-0.5.0`. It may be a CPU portability problem shared by these images that
only appears on some hosted runner CPUs, or another runner-specific failure.
The exact cause remains unresolved.

### `rel-0.5.0` gNB

Pairing the `rel-0.5.0` gNB with the known-good `rel-0.4.0` UE removes the
`SIGILL`, but reproduces the attachment failure:

```text
Waiting PHY to initialize ... done!
Attaching UE...
```

The tunnel never appears. This demonstrates that the `rel-0.5.0` gNB has an
interoperability problem independent of the `rel-0.5.0` UE portability issue.

## Container Build Changes

The sibling `srsRAN-docker` repository has no `v0.4.0` Git tag. Its release
history jumps from `v0.3.0` to `v0.5.0`, even though Docker Hub contains
`rel-0.4.0`. The older images lack source-revision OCI labels, but the
downloaded gNB binary embeds its upstream source revision:

- `rel-0.4.0` gNB: commit
  `2be82d8ea38e3a729850b702254952c04118cc38` from `main`
- `rel-0.7.0` gNB: commit
  `d2f4b70dda8e2c557d5b05a0ac5f92dbddda19bc` from `release_25_10`

These revisions are about 2,300 upstream commits apart.

By `v0.5.0`, the build had changed in several relevant ways:

- The gNB source changed from the moving srsRAN Project `main` branch to the
  `release_25_10` ref.
- The UE continued to use the moving srsRAN_4G `release_23_11` branch.
- The Makefile began passing explicit upstream refs and recording upstream
  commit labels.
- Neither Dockerfile pinned a CPU portability baseline for the UE build.

The `rel-0.7.0` labels identify:

- srsRAN-docker commit `46191e21d71115bfe421f841b0d9ce6e8053ca29`
- gNB ref `release_25_10`, commit
  `d2f4b70dda8e2c557d5b05a0ac5f92dbddda19bc`
- UE ref `release_23_11`, commit
  `eea87b1d893ae58e0b08bc381730c502024ae71f`

The OnRamp ZMQ configuration and container launch tasks were unchanged when
the images moved from `rel-0.4.0` to `rel-0.7.0`.

At the older gNB revision, the upstream ZMQ CI definition used an Amarisoft
UE. At the newer revision, srsRAN's own srsUE ZMQ job requests 6 CPUs and
26 GB RAM for each of the gNB and UE containers. The newer gNB also exposes
different lower-PHY execution profiles (`single`, `dual`, and `triple`).
Resource pressure or changed lower-PHY scheduling on the smaller
GitHub-hosted runner is a plausible explanation for the attachment failure,
but it has not yet been proven.

## OnRamp Changes

The CI repair branch adds:

- a compatibility pin to the known-good `rel-0.4.0` image pair;
- polling for `tun_srsue` instead of a fixed 10-second delay;
- idempotent default-route replacement;
- immediate failure when UE startup fails; and
- collection of the UE's internal `/tmp/ue.log`.

The readiness task should also tolerate a missing or exited container. In the
all-`rel-0.5.0` test, `community.docker.docker_container_exec` returned no
`rc`, causing the `until: ue_tunnel.rc == 0` condition itself to fail.

## Conclusions

1. The original OnRamp CI regression is caused by the srsRAN container image
   update, not by an insufficient startup delay.
2. The `SIGILL` observed with the `rel-0.5.0` UE is not a source-code
   difference from the known-good UE. All inspected UE images contain
   automatically selected AVX/AVX2 code, making CPU portability a shared
   risk that needs a controlled reproduction.
3. The `rel-0.5.0` gNB does not interoperate with the known-good `rel-0.4.0`
   UE using the current ZMQ configuration.
4. Pinning both OnRamp images to `rel-0.4.0` is the appropriate short-term
   recovery.
5. The durable fixes belong in `srsRAN-docker`: use reproducible upstream
   commits, compile the UE for an explicit CPU baseline, and test the
   gNB/UE ZMQ pair before publishing a release.

## Next Experiments

- Run the pending `rel-0.5.0` gNB test with
  `expert_execution.threads.lower_phy.execution_profile: single`.
- Build a UE image with automatic ISA detection disabled or with an explicit
  conservative x86-64 target, then test it repeatedly across hosted runners.
- Build the gNB from the last known-compatible upstream revision while
  retaining the newer Dockerfile and labels.
- Bisect srsRAN Project revisions between the `rel-0.4.0` build and
  `release_25_10` to find the ZMQ compatibility break.
- Test the newer gNB with a larger runner to separate scheduling/resource
  issues from protocol compatibility.
- Add a release smoke test in `srsRAN-docker` that starts the published gNB
  and UE together and verifies successful UE attachment.
