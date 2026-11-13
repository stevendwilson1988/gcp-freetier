#!/usr/bin/env bash
# Counts Compute Engine usage across EVERY project on the billing account,
# for the OpenTofu `external` data source in ../preflight.tf.
#
# stdin:  {"project_id": "...", "billing_account_id": "" | "...", "managed_label": "key=value"}
# stdout: flat JSON object of strings (the external data source requires strings).
#
# Resources carrying managed_label belong to this config and are left out, so
# re-planning never double counts. Any gcloud failure exits non-zero, which fails
# the plan: a failed API call must never read as zero usage.

set -euo pipefail

die() { echo "usage.sh: $*" >&2; exit 1; }

command -v gcloud >/dev/null || die "gcloud not found"
command -v jq >/dev/null || die "jq not found"

input=$(cat)
project_id=$(jq -er '.project_id' <<<"$input") || die "project_id missing from query"
billing=$(jq -r '.billing_account_id // ""' <<<"$input")
managed_label=$(jq -er '.managed_label' <<<"$input") || die "managed_label missing from query"
label_key=${managed_label%%=*}
label_val=${managed_label#*=}

if [[ -z "$billing" ]]; then
  info=$(gcloud billing projects describe "$project_id" --format=json) \
    || die "cannot read billing info for $project_id"
  billing=$(jq -r '.billingAccountName // ""' <<<"$info")
  billing=${billing#billingAccounts/}
fi
[[ -n "$billing" ]] || die "project $project_id has no billing account linked"

projects_json=$(gcloud billing projects list --billing-account="$billing" --format=json) \
  || die "cannot list projects on billing account $billing"
projects=$(jq -r '.[] | select(.billingEnabled == true) | .projectId' <<<"$projects_json")

free_regions='["us-west1","us-central1","us-east1"]'

# Accumulate every project's resources into one JSON array per type.
all_instances='[]'; all_disks='[]'; all_snapshots='[]'; all_addresses='[]'; all_images='[]'
checked=0

for p in $projects; do
  enabled=$(gcloud services list --project="$p" --enabled \
    --filter="config.name=compute.googleapis.com" --format="value(config.name)") \
    || die "cannot list services for $p"
  [[ -n "$enabled" ]] || continue # No Compute API: no Compute resources.
  checked=$((checked + 1))

  i=$(gcloud compute instances list --project="$p" --format=json)       || die "instances list failed for $p"
  d=$(gcloud compute disks list --project="$p" --format=json)           || die "disks list failed for $p"
  s=$(gcloud compute snapshots list --project="$p" --format=json)       || die "snapshots list failed for $p"
  a=$(gcloud compute addresses list --project="$p" --format=json)       || die "addresses list failed for $p"
  m=$(gcloud compute images list --project="$p" --no-standard-images --format=json) || die "images list failed for $p"

  all_instances=$(jq -c --argjson add "$i" '. + $add' <<<"$all_instances")
  all_disks=$(jq -c --argjson add "$d" '. + $add' <<<"$all_disks")
  all_snapshots=$(jq -c --argjson add "$s" '. + $add' <<<"$all_snapshots")
  all_addresses=$(jq -c --argjson add "$a" '. + $add' <<<"$all_addresses")
  all_images=$(jq -c --argjson add "$m" '. + $add' <<<"$all_images")
done

jq -n \
  --arg billing "$billing" \
  --arg checked "$checked" \
  --arg lk "$label_key" --arg lv "$label_val" \
  --argjson free "$free_regions" \
  --argjson inst "$all_instances" \
  --argjson disks "$all_disks" \
  --argjson snaps "$all_snapshots" \
  --argjson addrs "$all_addresses" \
  --argjson imgs "$all_images" '
  def unmanaged: map(select((.labels // {})[$lk] != $lv));
  def basename: split("/") | last;
  def region_of_zone: basename | sub("-[a-z]$"; "");
  def free_micro:
    (.machineType | basename) == "e2-micro"
    and ((.zone | region_of_zone) as $r | any($free[]; . == $r))
    and ((.scheduling.preemptible // false) | not)
    and ((.scheduling.provisioningModel // "STANDARD") == "STANDARD");

  ($inst | unmanaged) as $oi
  | ($disks | unmanaged) as $od
  | {
      billing_account:        $billing,
      projects_checked:       $checked,
      # Every status counts: a stopped VM can be started again.
      free_e2_micro:          ($oi | map(select(free_micro)) | length),
      paid_instances:         ($oi | map(select(free_micro | not)) | length),
      ipv4_in_use:            ($oi | map(select([.networkInterfaces[]?.accessConfigs[]?.natIP] | length > 0)) | length),
      disk_gb:                ($od | map(.sizeGb | tonumber) | add // 0),
      non_standard_disks:     ($od | map(select((.type | basename) != "pd-standard")) | length),
      snapshot_gb:            ($snaps | map((.storageBytes // "0" | tonumber) / 1073741824) | add // 0 | . * 100 | ceil / 100),
      static_external_ips:    ($addrs | map(select(.addressType == "EXTERNAL")) | length),
      custom_images:          ($imgs | length)
    }
  | map_values(tostring)
'
