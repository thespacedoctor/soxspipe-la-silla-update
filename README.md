# SOXS pipeline maintenance for the La Silla workstation

This page tells you how to update, run, and monitor the SOXS data-reduction pipeline (`soxspipe`) on the `wsxpl` workstation at La Silla. It is for the people who maintain the pipeline on that machine.

**Important:** `update-pipeline.sh` has not yet given a working install on `wsxpl`. The first run installed soxspipe 0.19.0, which could not use the `wsxpl` data folders. Use `--dry-run` first, and stay at the terminal during the next update.

## Contents

- [Make the private monit files](#make-the-private-monit-files)
- [Update the pipeline](#update-the-pipeline)
- [What the script does](#what-the-script-does)
- [Remove the reduced frames (optional)](#remove-the-reduced-frames-optional)
- [Use monit to control the pipeline](#use-monit-to-control-the-pipeline)
- [Repair Slack alerts without an update](#repair-slack-alerts-without-an-update)
- [Common errors](#common-errors)
- [Test the script](#test-the-script)

## Make the private monit files

This repository is public, so 2 private files stay on `wsxpl`. Make them once, as the `pipeline` user. The script never changes or deletes them.

1. Make the monit web settings file. Replace `MONIT_WEB_PASSWORD` with the real password:

   ```bash
   cat > ~/monit/monit-httpd.conf <<'EOF'
   set httpd port 8080 and
       use address localhost
       allow localhost
       allow pipeline:MONIT_WEB_PASSWORD
   EOF
   chmod 600 ~/monit/monit-httpd.conf
   ```

2. Save the Slack webhook. Replace `SLACK_WEBHOOK_URL` with the real URL:

   ```bash
   echo 'SLACK_WEBHOOK_URL' > ~/monit/slack-webhook-url
   chmod 600 ~/monit/slack-webhook-url
   ```

The script stops if `monit-httpd.conf` is missing, because the monit web page does not work without it. If `slack-webhook-url` is missing, the script gives a warning and continues. Monit then runs without Slack alerts, and each alert writes a line in `~/monit/monit.log`.

## Update the pipeline

You need:

- A login to `wsxpl` as the `pipeline` user, with the home folder `/diska/home/pipeline`.
- The [private monit files](#make-the-private-monit-files).
- At least 1 FITS file in a dated folder in `/data/raw`, such as `/data/raw/2026-01-19/`. No frames directly in `/data/raw`.
- No running `soxspipe` process. The script stops if it finds one.

1. Log in:

   ```bash
   ssh -X pipeline@wsxpl
   ```

2. Download the script and run the update:

   ```bash
   wget --no-check-certificate -O ~/update-pipeline.sh https://raw.githubusercontent.com/thespacedoctor/soxspipe-la-silla-update/main/update-pipeline.sh && bash ~/update-pipeline.sh
   ```

To see what the script will do first, run `bash ~/update-pipeline.sh --dry-run`. This changes nothing.

**Warning:** `wsxpl` does not trust the certificate issuer of the GitHub downloads, so `wget` uses `--no-check-certificate` for this script, the miniforge installer, and the monit files. `wget` does not confirm that these files come from GitHub. They all run as the `pipeline` user, and monit runs its files again and again. Someone who controls the network path could run their own code on `wsxpl`.

The script asks no questions. The last line of a good run gives the installed version, for example:

```text
Finished: soxspipe 0.19.1 is installed and monit is running.
```

If a step fails, the script stops and names the step. It does not start monit after a failure. Fix the problem and run the script again.

It is safe to run the script again after a failure or a lost connection, because each run starts from the beginning.

## What the script does

The script runs these steps in order:

1. Checks the user name, the home folder, the private monit files, the `monit` and `wget` commands, `/data/reduced`, and the FITS files in `/data/raw`.
2. Downloads the miniforge installer and the monit files without a certificate check. A failed download leaves the old install in place.
3. Replaces `~/monit/monit2slack.rb` and `~/monit/soxspipe-cycle.sh` with the copies in the `monit` folder of this repository, and sets the private files to mode 600. Stops if `monit -t` finds a problem in the new settings. This leaves the old conda install in place and monit running.
4. Stops monit.
5. Stops with an error if a `soxspipe` process is running. The message lists the processes. monit stays stopped, so wait for the processes to finish and run the script again.
6. Deletes `~/miniforge3`, `~/.conda`, `~/.condarc`, and `~/soxspipe_reductions`.
7. Installs miniforge in `~/miniforge3` and sets up conda for new shells.
8. Creates the `soxspipe` conda environment with Python 3.12, Ruby, and the latest `soxspipe` from conda-forge, which must be 0.19.1 or later. `monit2slack.rb` needs the Ruby.
9. Runs `soxspipe prep . --vlt` in a new `~/soxspipe_reductions` workspace.
10. Runs `soxspipe session ls` and stops if it fails or lists no current session. A good `prep` does not prove that later commands work.
11. Replaces `~/.monitrc` with the copy in the `monit` folder of this repository. The first run keeps the old settings in `~/.monitrc.bak`.
12. Starts monit.

**Warning:** Step 6 deletes the workspace database, `soxspipe.db`, and its `backups/` folder. This removes the QC history that the database holds. The frames in `/data/raw` and `/data/reduced` stay in place.

Miniforge is a small installer for the conda package manager. It is not part of Anaconda. It uses the community conda-forge channel, so installing it on ESO machines does not break any license.

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

4. Run `update-pipeline.sh`. It starts monit again at the end.

## Use monit to control the pipeline

Monit is a small tool that monitors and restarts processes. Its settings are in `~/.monitrc`. The update script replaces this file, so make any lasting change in `monit/monitrc` in this repository. Monit runs a cycle every 60 seconds, and it runs the pipeline in batches of 25 recipes.

Monit does these things:

- It monitors the load on the machine.
- It starts a reduction in `~/soxspipe_reductions` if no reduction cycle is in progress.
- It stops and restarts the pipeline if the pipeline runs for longer than a set timeout.
- It gives La Silla staff a view of the pipeline status, and a way to start and stop the pipeline with one click.

### Start monit

Run this from any folder:

```bash
monit
```

### View the pipeline status

```bash
ssh -X pipeline@wsxpl
monit-web
```

`monit-web` is an alias in `.bashrc` for `firefox localhost:8080 &`.

The page asks you to log in the first time you open it. Use the login details of the `pipeline` account on this machine.

Select the **soxspipe** link to see the logs of the previous run of 25 recipes. If the pipeline is failing, the status on the page changes and the logs show the problem.

### Start and stop the pipeline from monit

1. On the monit home page, select the **soxspipe** link.
2. Scroll to the bottom of the page.
3. Select **Disable monitoring** to stop the pipeline. The home page then shows the task as disabled.
4. To start the pipeline again, go back to the same page and select **Enable monitoring**.

### Stop monit completely

```bash
monit quit
```

## Repair Slack alerts without an update

Use these steps if Slack alerts fail with `bad interpreter`, and you do not want to run the update script. The update script deletes `soxspipe.db` and its QC history, and these steps do not.

```bash
~/miniforge3/bin/conda install --yes --name soxspipe ruby
sed -i '1s|.*|#!/diska/home/pipeline/miniforge3/envs/soxspipe/bin/ruby|' ~/monit/monit2slack.rb
```

## Common errors

### soxspipe prep did not finish

The update stops with this message if `soxspipe prep` leaves a partial workspace. `soxspipe prep` shows no error in this case.

A FITS frame directly in `/data/raw` causes this. The script checks for such frames before it deletes anything.

### PackagesNotFoundInChannelsError during "Installing soxspipe"

The update stops with this error if conda-forge does not yet offer the `soxspipe` version that the script needs. A new version can take some hours to appear after its release. The script has already deleted the old install at this step, and monit is stopped.

Wait, and then run the script again. To avoid this error, confirm the version before you start. This command must list the version:

```bash
wget -qO- --no-check-certificate https://conda.anaconda.org/conda-forge/noarch/current_repodata.json | grep -o 'soxspipe-[0-9.]*-[^"]*conda' | sort -u
```

### soxspipe session ls failed after soxspipe prep

The update stops with this message, or with `soxspipe session ls did not list a current session`, if `soxspipe` cannot use the new workspace. Monit stays stopped, because every monit cycle would fail.

Read the lines above the message for the error from `soxspipe`. Then:

1. Check that `~/soxspipe_reductions/raw` is a link to `/data/raw`.
2. Fix the problem and run the script again.

### Database timeout or corruption

Timeouts or corruption in the internal database can stall the pipeline. If an error points to the database:

1. Disable the monit task (see [Start and stop the pipeline from monit](#start-and-stop-the-pipeline-from-monit)).
2. Refresh the workspace. This rebuilds the database:

   ```bash
   cd ~/soxspipe_reductions
   conda activate soxspipe
   soxspipe prep -r
   ```

3. Enable the monit task.

### Recipe failures

A recipe can fail in many ways. The code often forces a failure when the data is not good enough to make a good product.

To find the logs of failed recipes:

```bash
cd ~/soxspipe_reductions/reduced/
find . -name "*ERROR*"
```

To read a log, use `cat`:

```bash
cat ./sessions/base/reduced/2026-01-19/soxs-mflat/20260119T122357_NIR_3_MFLAT_QTH_SLIT0_5_7_5S_SOXS_ERROR.log
```

The sections below show the last lines of each error.

#### MDARK failures

If a master dark has a large negative median flux, the pipeline fails and does not use this poor calibration:

```text
ValueError: The master dark has a negative median flux level of -29.05 e-. Please check the raw input frames.
Recipe Command: soxspipe mdark sof/20260112T182544_NIR_3_MDARK_60_0S_SOXS.sof -s ./soxspipe.yaml
```

If the range of pixel fluxes in a master dark is too large, the pipeline also fails:

```text
ValueError: The master dark has a large flux range of 32.13 e-/s. Please check the raw input frames.
Recipe Command: soxspipe mdark sof/20260123T144358_NIR_3_MDARK_2_0S_SOXS.sof -s ./soxspipe.yaml
```

#### Data-organiser failures

The data organiser has sometimes predicted the wrong path for an earlier calibration product. This should not happen. Planned: a later release will fix it.

```text
FileNotFoundError: the input file `./sessions/base/reduced/2026-01-28/soxs-mbias/20260129T130359_VIS_2X1_3_MBIAS_SOXS.fits` does not appear to exist
Recipe Command: soxspipe mflat sof/20260129T144038_VIS_2X1_3_MFLAT_QTH_SLIT1_5_7_0S_SOXS.sof -s ./soxspipe.yaml
```

#### MFLAT failures

Low flux in the flat frames causes this failure. The pipeline does not use low-quality flats:

```text
ValueError: FLUX IN THE INPUT FLAT FRAMES IS TOO LOW TO PROCEED. PLEASE CHECK THE RAW FRAMES
```

A master flat can also fail when the polynomial fit to the order edges does not converge. This should not happen often:

```text
File "soxspipe/commonutils/detect_order_edges.py", line 646, in plot_results
    axisAfitup, axisBfitup = zip(
ValueError: not enough values to unpack (expected 2, got 0)
```

#### spat_solution failures

The pipeline may detect too few arc lines to make a good dispersion solution. Check the raw data. If the raw data looks good, the format may have shifted by more than the pipeline can handle without help.

```text
ValueError: Only 44.04% of the input line-list lines were detected on the pinhole frame. Please check the quality of the raw frames.
Recipe Command: soxspipe spat_solution sof/20260111T095625_NIR_3_SSOL_MULTPIN_15_0S_SOXS.sof -s ./soxspipe.yaml
```

Some multi-pinhole frames do not show all 9 pinholes. This was true early in the commissioning runs.

```text
AttributeError: All 9 pinholes cannot be seen in the data. A dispersion solution cannot be created.
Recipe Command: soxspipe spat_solution sof/20260124T085418_VIS_1X1_1_SSOL_MULTPIN_30_0S_SOXS.sof -s ./soxspipe.yaml
```

#### Nodding failures

Rarely, not all nodding frames of an OB reach the archive. The OB may have stopped before it finished.

```text
Exception: Found 1 A frames and 0 B frames. The number of A and B frames must be the same for nodding reductions.
Recipe Command: soxspipe nod sof/20260124T071706_NIR_3_NOD_STD_FLUX_SLIT1_5_1_7S_SOXS.sof -s ./soxspipe.yaml
```

## Test the script

The tests need Docker and `shellcheck`. They run in a throwaway container with stand-ins for monit, wget, conda, Ruby, and `soxspipe`, and they never touch a real install.

```bash
tests/run-tests.sh
```
