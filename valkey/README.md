# valkey

Homelab **Valkey** (standalone) — a thin wrapper around the official
[`valkey-io/valkey-helm`](https://github.com/valkey-io/valkey-helm) chart.
Replaces the deprecated Bitnami-legacy Valkey chart.

## What it deploys

- A single Valkey instance (Deployment, `replicas: 1`) using the official
  `valkey/valkey` image.
- **AOF persistence**: every write is appended to a log on a PVC mounted at
  `/data` and replayed on restart, so data survives pod restarts.
- **ACL auth** for the `default` user; the password comes from an out-of-band
  Secret (never in Git).

## Secret (not in Git)

Create the password Secret before deploying:

```sh
kubectl -n valkey create secret generic valkey-acl \
  --from-literal=default="$(openssl rand -base64 24)"
```

`default` is the ACL username; the chart reads the password from that key
(`auth.usersExistingSecret`).

## Connect

Find the service with `kubectl -n valkey get svc`, then connect on port `6379`
as user `default` with the password from the `valkey-acl` Secret.

## Upgrading Valkey

Bump the dependency `version` in `Chart.yaml` (chart from
`https://valkey.io/valkey-helm/`) and run `helm dependency update`.
