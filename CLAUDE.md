# GCP Free Tier Project

This repo holds scripts that manage a Google Cloud Platform (GCP) project and its billing account.

## The rule: never cost money

Everything must stay within Google Cloud's **Always Free** limits. **No charges, ever.** Every script, change and recommendation in this repo has to meet that rule. When cost and convenience conflict, cost wins.

**GCP has no built-in spending cap.** Once the billing account is upgraded past the free trial, Google bills for any usage over the free limits. Budgets only send alerts; they don't stop spending. That makes this file and the safeguards below the only protection, so be stricter here than you would be on OCI.

**The $300 trial credit doesn't count as free.** Don't use trial credit for anything outside Always Free. When the trial ends, everything must keep running at $0.

## Always Free limits (per billing account, not per project)

Check these against Google's current list before relying on them, because Google changes it:
https://cloud.google.com/free/docs/free-cloud-features

| Resource | Always Free limit |
|---|---|
| Compute Engine VM | **1** non-preemptible `e2-micro`, only in **`us-west1`, `us-central1` or `us-east1`** (720 hours/month = one VM running all month) |
| Persistent disk | 30 GB-month **standard** (`pd-standard`) total, across all disks |
| Snapshots | 5 GB-month (us-west1, us-central1, us-east1, asia-east1, europe-west1) |
| Network egress | **1 GB/month** from North America to all destinations except China and Australia |
| Cloud Storage | 5 GB-month **Standard** class, US regions only (us-west1, us-central1, us-east1); 5k Class A / 50k Class B operations |
| Cloud Run | 2M requests, 180k vCPU-seconds, 360k GiB-seconds per month |
| Cloud Run functions | 2M invocations per month |
| Firestore | 1 GB storage; 50k reads, 20k writes, 20k deletes per day |
| BigQuery | 1 TB queries, 10 GB storage per month |
| Pub/Sub | 10 GB messages per month |
| Artifact Registry | 0.5 GB storage |
| Secret Manager | 6 active secret versions, 10k access operations per month |

## GCP-specific traps

These are the usual ways a "free" GCP setup ends up being billed:

- **Wrong region or zone.** An `e2-micro` outside the three free regions is billed. So is any machine type other than `e2-micro`, including `e2-small` and `f1-micro`.
- **Wrong disk type.** The console and some defaults use `pd-balanced`, which is billed. Always pass `--boot-disk-type=pd-standard`, and keep all disks together at 30 GB or less.
- **A second VM.** The free allowance is 720 hours a month. Two `e2-micro` VMs running all month means one is billed. Stopped VMs don't use hours, but their disks still count toward the 30 GB.
- **Spot or preemptible VMs** aren't covered by the free tier.
- **Premium OS images** (Windows, RHEL, SLES) carry license fees. Use Debian or Ubuntu.
- **Egress.** 1 GB a month is tiny. Traffic served through a Cloudflare Tunnel counts as egress, and so do downloads and `apt` mirrors outside GCP. Put heavy or public-facing workloads on the OCI tenancy instead.
- **IP addresses.** A reserved static IP that isn't attached to a running VM is billed. Google also charges for in-use external IPv4 addresses; confirm the free tier covers the `e2-micro`'s IP before relying on it.
- **Paid services with no free tier:** Cloud NAT, load balancers, Cloud SQL, Memorystore, Filestore, GKE nodes, Cloud Armor, GPUs, VPN and Interconnect. Don't create them.
- **Logging and monitoring.** Stay within the free ingestion allotment. Don't route logs to BigQuery or Cloud Storage sinks, which accumulate storage.

## Rules for scripts

1. **Only use Always Free resources and options.** Use `e2-micro` in an allowed region, `pd-standard` disks, Standard-class buckets in a free US region, and Debian or Ubuntu images. Hard-code the allowed region and zone, and validate them at the top of the script.
2. **Check usage before creating anything.** A script that creates a resource must first count what already exists across **every project on the billing account**: the number of `e2-micro` instances, total persistent disk GB, snapshot GB, bucket storage and static IPs. It stops if the new resource would push past a limit. Running a script twice must never double the resources.
3. **Prefer idempotent scripts.** Reuse existing resources by name instead of creating duplicates.
4. **Pin sizes explicitly.** Set the machine type, zone, disk type and disk size explicitly; don't rely on gcloud or console defaults.
5. **Clean up completely.** Teardown scripts must delete disks, snapshots, static IPs and images. Deleting a VM can leave disks behind (`--keep-disks`, or `auto-delete=false`), and they keep counting toward the 30 GB.
6. **When in doubt, don't.** If you can't confirm that a resource or option is Always Free, don't create it. Flag it and ask.
7. **Enable only the APIs a script needs.** Enabling an API is free, but it makes paid resources possible to create.

## Ask before

- Any change that could incur a charge, even a small one.
- Upgrading from the free trial to a paid billing account, or linking a billing account to a new project.
- Changing or removing the budget, the billing kill-switch or quota overrides.
- Destructive operations: deleting instances, disks, snapshots, buckets or projects.
- Changing IAM policies or creating service account keys.

## Safeguards outside this repo

Set these up **before** creating any resources:

1. **A budget with alerts** on the billing account, for example $1 with thresholds at 50%, 90% and 100%. This only notifies; it doesn't stop anything.
2. **A billing kill-switch:** the budget publishes to a Pub/Sub topic, and a Cloud Run function disables billing on the project when cost goes above $0. This is the only hard stop GCP offers. It runs within the Pub/Sub and Cloud Run free tiers. Disabling billing stops paid services, and resources can be deleted if billing stays off, so treat it as an emergency brake.
3. **Lowered quotas (optional but recommended):** set CPU and disk quota overrides so that only one `e2-micro` and 30 GB of `pd-standard` can exist in the free regions, and 0 everywhere else. Unlike this file, GCP enforces quotas.

## Repo conventions

- Bash plus `gcloud` CLI plus `jq`. Scripts use `set -euo pipefail`.
- Capture command output into variables before acting on it. Don't use `< <(...)` for usage checks, because a failed API call there silently reads as zero usage.
- Authenticate with `gcloud auth login` or Application Default Credentials. Avoid service account key files.
- Never commit credentials. `.gitignore` excludes keys, key JSON files and `.env`.
- The OCI tenancy lives in the sibling repo `../oci-freetier`. It has far more free compute and 10 TB of egress, so it's the default home for anything heavy.
