# First-time setup of the SOXS pipeline on `wsxpl`

This page tells you how to prepare a new machine for the SOXS data-reduction pipeline (`soxspipe`) at La Silla, before the first run of the update script. It is for the people who set up the `wsxpl` workstation. To update a machine that is already set up, use the [README](README.md).

## Contents

- [What the machine needs first](#what-the-machine-needs-first)
- [Make the private monit files](#make-the-private-monit-files)
- [Add the monit-web alias](#add-the-monit-web-alias)
- [Run the update](#run-the-update)
- [Repair Slack alerts without an update](#repair-slack-alerts-without-an-update)

## What the machine needs first

The update script does not make these things. It stops if one is missing. Making them needs administrator access, so ask the administrator of the machine:

- A `pipeline` account with the home folder `/diska/home/pipeline`.
- The `monit` and `wget` commands.
- The folder `/data/raw`, with at least 1 FITS frame in a dated folder, such as `/data/raw/2026-01-19/`. No frame directly in `/data/raw`.
- The folder `/data/reduced`, which the `pipeline` user can write to.
- Network access to GitHub and conda-forge.

The script does not make the `monit-web` alias, and it does not check for it. See [Add the monit-web alias](#add-the-monit-web-alias).

## Make the private monit files

This repository is public, so 2 private files stay on `wsxpl`. Make them once, as the `pipeline` user. The script never changes or deletes them.

1. Make the folder for the files:

   ```bash
   mkdir -p ~/monit
   ```

2. Make the monit web settings file. Replace `MONIT_WEB_PASSWORD` with the real password:

   ```bash
   cat > ~/monit/monit-httpd.conf <<'EOF'
   set httpd port 8080 and
       use address localhost
       allow localhost
       allow pipeline:MONIT_WEB_PASSWORD
   EOF
   chmod 600 ~/monit/monit-httpd.conf
   ```

3. Save the Slack webhook. Replace `SLACK_WEBHOOK_URL` with the real URL:

   ```bash
   echo 'SLACK_WEBHOOK_URL' > ~/monit/slack-webhook-url
   chmod 600 ~/monit/slack-webhook-url
   ```

4. Clear the shell history of this login, so that the password and the webhook are not saved in it:

   ```bash
   history -c
   ```

The script stops if `monit-httpd.conf` is missing, because the monit web page does not work without it. If `slack-webhook-url` is missing, the script gives a warning and continues. Monit then runs without Slack alerts, and each alert writes a line in `~/monit/monit.log`.

## Add the monit-web alias

`monit-web` opens the monit status page in a browser. It is an alias in `.bashrc` for `firefox localhost:8080 &`. To add it, run this as the `pipeline` user:

```bash
echo "alias monit-web='firefox localhost:8080 &'" >> ~/.bashrc
```

The alias works the next time you log in.

## Run the update

Follow [Update the pipeline](README.md#update-the-pipeline) in the README. The update script installs the pipeline, makes the workspace, and starts monit.

## Repair Slack alerts without an update

Use these steps if Slack alerts fail with `bad interpreter`, and you do not want to run the update script. The update script deletes `soxspipe.db` and its QC history, and these steps do not.

```bash
~/miniforge3/bin/conda install --yes --name soxspipe ruby
sed -i '1s|.*|#!/diska/home/pipeline/miniforge3/envs/soxspipe/bin/ruby|' ~/monit/monit2slack.rb
```
