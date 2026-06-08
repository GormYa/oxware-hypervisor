---
name: Marketplace Submission
about: Submit a plugin or VM template to the OXware Marketplace
title: "[Marketplace] <your plugin/template name>"
labels: marketplace
---

## Submission

**Type:** (plugin / VM template / automation workflow)

**Name:**

**Description:** (1-2 sentences, plain language)

**Category:** (os / app / devops / plugin)

**Author:**

**Version:**

**Tags:** (comma-separated)

## For plugins

- Attach your `plugin.py` or `.zip` to this issue.
- Confirm it passes panel validation (Settings > Plugins > Develop > Validate)
  with no critical security warnings.
- `PLUGIN_META` is present with id/name/version/author/description/api_version.

## For VM templates

- Image URL (qcow2/img) or describe how the image is built.
- Default vm_spec: vCPUs / RAM (MB) / disk (GB).

## Checklist

- [ ] No malware, no obfuscated code
- [ ] MIT-compatible license (or state the license)
- [ ] Tested on Ubuntu 22.04 / Debian 12

We review submissions and add approved entries to
`https://oxware.top/marketplace/index.json`.
