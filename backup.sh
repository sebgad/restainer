#!/bin/sh

# Make sure the script aborts if any step is failing
set -euo pipefail

lastLogfile="/var/log/backup-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

copyErrorLogMariadb() {
  cp ${lastLogfile} /var/log/backup-error-last-mariadb.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

start=`date +%s`
rm -f ${lastLogfile}
echo "--- Starting Backup at $(date +"%Y-%m-%d %H:%M:%S") ---"
echo "--- Starting Backup at $(date) ---" >> ${lastLogfile}

if [ -f "/hooks/pre-backup.sh" ]; then
    echo "Starting pre-backup script ..."
    /hooks/pre-backup.sh
else
    echo "Pre-backup script not used ..."
fi

logLast "BACKUP_CRON: ${BACKUP_CRON}"
logLast "RESTIC_TAG: ${RESTIC_TAG}"
logLast "RESTIC_FORGET_ARGS: ${RESTIC_FORGET_ARGS}"
logLast "RESTIC_JOB_ARGS: ${RESTIC_JOB_ARGS}"
logLast "RESTIC_REPOSITORY: ${RESTIC_REPOSITORY}"

# Do not save full backup log to logfile but to backup-last.log
restic backup /data ${RESTIC_JOB_ARGS} --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} >> ${lastLogfile} 2>&1

backupRC=$?
logLast "Finished backup at $(date)"
if [[ $backupRC == 0 ]]; then
    echo "Backup Successful"
else
    echo "Backup Failed with Status ${backupRC}"
    restic unlock
    copyErrorLog
fi

if [ -n "${MARIADB_DATABASE}" ]; then
    # Save MARIADB data if
    mariadb-dump -h 127.0.0.1 \
                 -u $MARIADB_BACKUP_USER \
                 -p$MARIADB_BACKUP_PW \
                 $MARIADB_DATABASE | restic backup ${RESTIC_JOB_ARGS} \
                                            --tag=${RESTIC_TAG?"Missing environment variable RESTIC_TAG"} \
                                            --stdin-filename $MARIADB_DATABASE.sql --stdin  >> ${lastLogfile} 2>&1

    backupRCMariadb=$?
    logLast "Finished backup at $(date)"
    if [[ $backupRCMariadb == 0 ]]; then
        echo "MariaDB backup Successful"
    else
        echo "MariaDB Failed with Status ${backupRCMariadb}"
        restic unlock
        copyErrorLogMariadb
    fi
fi

if [[ $backupRC == 0 ]] && [ -n "${RESTIC_FORGET_ARGS}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    restic forget ${RESTIC_FORGET_ARGS} >> ${lastLogfile} 2>&1
    rc=$?
    logLast "Finished forget at $(date)"
    if [[ $rc == 0 ]]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${rc}"
        restic unlock
        copyErrorLog
    fi
fi

if [ -f "/hooks/post-backup.sh" ]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh $backupRC
else
    echo "Post-backup script not found ..."
fi

end=`date +%s`
echo "--- Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds ---"
