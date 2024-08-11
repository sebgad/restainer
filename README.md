# Restainer
A docker container to automate [restic backups](https://restic.github.io/)

This repository is heavily based on [https://github.com/lobaro/restic-backup-docker](https://github.com/lobaro/restic-backup-docker).

It is intended to use in combination with podman pods and adds the feature to store mariadb databases inside a pod.

## Hooks

If you need to execute a script before or after each backup or check, you need to add your hook scripts in the container folder `/hooks`:
```
-v ~/home/user/hooks:/hooks
```

Call your pre-backup script `pre-backup.sh` and post-backup script `post-backup.sh`. You can also have separate scripts when running data verification checks `pre-check.sh` and `post-check.sh`.

Please don't hesitate to report any issues you find. **Thanks.**

# Test the container

Clone this repository:
```
git clone https://github.com/sebgad/restainer
cd restainer
```

Build the container (the container is named `backup-test`):
```
./build.sh
```

Run the container:
```
./run.sh
```

This will run the container `backup-test` with the name  `backup-test`. Existing containers with that name are completely removed automatically.

The container will back up `~/test-data` to a repository with password `test` at `~/test-repo` every minute. The repository is initialized automatically by the container. If you'd like to change the arguments passed to `restic init`, you can do so using the `RESTIC_INIT_ARGS` env variable.

To enter your container execute:
```
docker exec -ti backup-test /bin/sh
```

Now you can use restic [as documented](https://restic.readthedocs.io/en/stable/), e.g. try to run `restic snapshots` to list all your snapshots.

## Logfiles
Logfiles are inside the container. If needed, you can create volumes for them.
```
docker logs
```
Shows `/var/log/cron.log`.

Additionally you can see the full log, including restic output, of the last execution in `/var/log/backup-last.log`. When the backup fails, the log is copied to `/var/log/restic-error-last.log`. If configured, you can find the full output of the mail notification in `/var/log/mail-last.log`.

# Use the running container

Assuming the container name is `restic-backup-var`, you can execute restic with:

    docker exec -ti restic-backup-var restic

## Backup

To execute a backup manually, independent of the CRON, run:

    docker exec -ti restic-backup-var /bin/backup

Back up a single file or directory:

    docker exec -ti restic-backup-var restic backup /data/path/to/dir --tag my-tag

## Data verification check

To verify backup integrity and consistency manually, independent of the CRON, run:

    docker exec -ti restic-backup-var /bin/check

## Restore

You might want to mount a separate host volume at e.g. `/restore` to not override existing data while restoring.

Get your snapshot ID with:

    docker exec -ti restic-backup-var restic snapshots

e.g. `abcdef12`

     docker exec -ti restic-backup-var restic restore --include /data/path/to/files --target / abcdef12

The target is `/` since all data backed up should be inside the host mounted `/data` dir. If you mount `/restore` you should set `--target /restore` and the data will end up in `/restore/data/path/to/files`.

# Customize the Container

The container is set up by setting [environment variables](https://docs.docker.com/engine/reference/run/#/env-environment-variables) and [volumes](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems).

## Environment variables

* `RESTIC_REPOSITORY` - the location of the restic repository. Default `/mnt/restic`. For S3: `s3:https://s3.amazonaws.com/BUCKET_NAME`
* `RESTIC_PASSWORD` - the password for the restic repository. Will also be used for restic init during first start when the repository is not initialized.
* `RESTIC_TAG` - Optional. To tag the images created by the container.
* `BACKUP_CRON` - A cron expression to run the backup. Note: The cron daemon uses UTC time zone. Default: `0 */6 * * *` aka every 6 hours.
* `CHECK_CRON` - Optional. A cron expression to run data integrity check (`restic check`). If left unset, data will not be checked. Note: The cron daemon uses UTC time zone. Example: `0 23 * * 3` to run 11PM every Tuesday.
* `RESTIC_FORGET_ARGS` - Optional. Only if specified, `restic forget` is run with the given arguments after each backup. Example value: `-e "RESTIC_FORGET_ARGS=--prune --keep-last 10 --keep-hourly 24 --keep-daily 7 --keep-weekly 52 --keep-monthly 120 --keep-yearly 100"`
* `RESTIC_INIT_ARGS` - Optional. Allows specifying extra arguments to `restic init` such as a password file with `--password-file`.
* `RESTIC_JOB_ARGS` - Optional. Allows specifying extra arguments to the backup job such as limiting bandwith with `--limit-upload` or excluding file masks with `--exclude`.
* `RESTIC_DATA_SUBSET` - Optional. You can pass a value to `--read-data-subset` when a repository check is run. If left unset, only the structure of the repository is verified. Note: `CHECK_CRON` must be set for check to be run automatically.

## Volumes
* `/data` - This is the data that gets backed up. Just [mount](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems) it to wherever you want.

