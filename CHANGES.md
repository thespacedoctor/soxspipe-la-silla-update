# Changes

**FEATURE**: Add `update-pipeline.sh` and a README converted from the La Silla maintenance manual (DY-2096)
**FEATURE**: Install the monit files from the update script, with secrets in private files on `wsxpl` (DY-2096)
**FIXED**: Download with `--no-check-certificate` because `wsxpl` does not trust the GitHub certificate issuer (DY-2096)
**FIXED**: Install Ruby in the `soxspipe` environment so Slack alerts work, and stop Slack problems from failing monit (DY-2096)
