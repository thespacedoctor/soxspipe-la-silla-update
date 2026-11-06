# Update the SOXS pipeline at La Silla

This page tells you how to update the SOXS data-reduction pipeline (`soxspipe`) on the `wsxpl` workstation at La Silla. It is for the people who look after that machine, and you do not need to know how to code. It assumes the pipeline is already installed. For a new machine, use [FIRST-TIME-SETUP.md](FIRST-TIME-SETUP.md). For daily use of monit and for recipe errors, use the [Google Doc](https://docs.google.com/document/d/1ZozFFMVKCivSxaRjlXnS8ZHM_fDb9JWcQbAugr4UOV0/edit?usp=sharing).

## Before you start

Check these things first:

- You can log in to `wsxpl` as the `pipeline` user.
- The private monit file `monit-httpd.conf` is on the machine. The Slack file `slack-webhook-url` is optional, but without it there are no Slack alerts. [FIRST-TIME-SETUP.md](FIRST-TIME-SETUP.md) shows how to make both.
- Each raw frame is in a dated folder in `/data/raw`, such as `/data/raw/2026-01-19/`. No frame is directly in `/data/raw`. There is at least 1 frame.
- No `soxspipe` process is running. The script stops if it finds one.

## Update the pipeline

1. Log in:

   ```bash
   ssh -X pipeline@wsxpl
   ```

2. Download the script and run the update:

   ```bash
   wget --no-check-certificate -O ~/update-pipeline.sh https://raw.githubusercontent.com/thespacedoctor/soxspipe-la-silla-update/main/update-pipeline.sh && bash ~/update-pipeline.sh
   ```

3. Wait for the last line. The script asks no questions. The last line of a good run gives the installed version, for example:

   ```text
   Finished: soxspipe 0.19.1 is installed and monit is running.
   ```

Optional: to see what the script will do first, run `bash ~/update-pipeline.sh --dry-run`. This changes nothing, and it lists any problems that it finds.

It is safe to run the script again after a failure or a lost connection, because each run starts from the beginning.

**Warning:** `wsxpl` does not trust the certificate issuer of the GitHub downloads, so the command above turns off the certificate check (`--no-check-certificate`). The script does the same for its other downloads. This means the machine cannot confirm that the files come from GitHub. The files run as the `pipeline` user, and monit runs some of them again and again. Someone who controls the network path could run their own code on `wsxpl`.

## What the script does

- Checks that you are logged in to the right account and that the machine is ready. If something is wrong, it stops before it changes anything.
- Downloads the new installer and the monitoring settings. If a download fails, the old pipeline stays in place.
- Updates the monitoring tool's helper files and checks the new settings.
- Stops the monitoring tool, monit.
- Stops if the pipeline is still running. Wait for it to finish, then run the script again.
- Deletes the old pipeline, its settings, its workspace, and the workspace database with its backups. This removes the quality-control history in that database. Your raw and reduced frames stay in place.
- Installs a new copy of the pipeline and the software it needs.
- Sets up a new workspace that uses the raw and reduced data folders.
- Checks that the pipeline works in the new workspace.
- Installs the new monitoring settings. The first update keeps a backup of the old settings.
- Starts monit, which restarts the pipeline.

## Remove the reduced frames (optional)

If you remove the frames in `/data/reduced`, the pipeline reduces all the frames in `/data/raw` again. The script never does this. Decide for yourself, and do it before you run the script:

1. Stop monit:

   ```bash
   monit quit
   ```

2. Make sure that no `soxspipe` process is running. If this command shows a process, wait for it to finish:

   ```bash
   ps -ef | grep [s]oxspipe
   ```

3. Remove the frames:

   ```bash
   rm -rf /data/reduced/*
   ```

4. Run the update. It starts monit again at the end.

## If the update stops

When a step fails, the script stops and prints 3 lines at the end:

- The step that failed.
- Whether monit is still running. If the script did not stop monit, it deleted nothing and the old pipeline still works.
- A reminder to fix the problem and run the script again.

The script never starts monit after a failure. Find your message below. If it is not here, read the message, fix the problem if you can, and run the update again. If you cannot fix it, send the lines above to the people who maintain the pipeline.

### FITS frames sit directly in /data/raw

Nothing was changed, and monit is still running. Move each frame into its dated folder, such as `/data/raw/2026-01-19/`, then run the update again.

### soxspipe is still running

Monit is stopped, and nothing was deleted. Wait for the pipeline to finish, then run the update again.

### The private file is missing

The message says that a private file, `monit-httpd.conf`, is missing. Nothing was changed. Make the file as [FIRST-TIME-SETUP.md](FIRST-TIME-SETUP.md) describes, then run the update again.

### soxspipe prep did not finish

The pipeline did not finish setting up the new workspace. The old pipeline is already deleted at this step, and monit is stopped. Run the update again. If it happens again, send the lines above the message to the people who maintain the pipeline.

### PackagesNotFoundInChannelsError

The package site, conda-forge, does not yet have the new `soxspipe` version. A new version can take some hours to appear after its release. The old pipeline is already deleted at this step, and monit is stopped. Wait some hours, then run the update again.

### soxspipe session ls failed

The update stops with this message, or with `soxspipe session ls did not list a current session`, if the pipeline cannot use the new workspace. The old pipeline is already deleted at this step, and monit stays stopped. Send the lines above the message to the people who maintain the pipeline, then run the update again after they fix the problem.
