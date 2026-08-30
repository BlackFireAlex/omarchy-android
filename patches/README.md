# Patch policy

Each patch in this directory must be recreated against the pinned clean
upstream revision, explain the Android constraint it addresses, and include a
reproduction or smoke test. Experimental snapshots and generated build output
do not belong here.

Patch directories correspond to components in `manifest/components.lock`.
Checksums and base revisions are recorded in `manifest/patches.lock`.
`scripts/verify-patches.sh` applies each complete series to a temporary clone
of its pinned pristine checkout.
