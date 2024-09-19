#!/bin/sh

# Make sure the script aborts if any step is failing
set -euo pipefail

lastLogfile="/var/log/backup-last.log"
lastLogMailFile="/var/log/backup-email-last.log"

copyErrorLog() {
  cp ${lastLogfile} /var/log/backup-error-last.log
}

copyErrorLogMariadb() {
  cp ${lastLogfile} /var/log/backup-error-last-mariadb.log
}

logLast() {
  echo "$1" >> ${lastLogfile}
}

LogMail() {
  echo "$1" >> ${lastLogMailFile}
}

start=`date +%s`
rm -f ${lastLogfile}
rm -f ${lastLogMailFile}

touch ${lastLogfile}
touch ${lastLogMailFile}

echo "--- Starting Backup ${RESTIC_TAG} at $(date +"%Y-%m-%d %H:%M:%S") ---"
echo "--- Starting Backup ${RESTIC_TAG} at $(date) ---" >> ${lastLogfile}

if [ -f "/hooks/pre-backup.sh" ]; then
    echo "Starting pre-backup script ..."
    /hooks/pre-backup.sh
else
    echo "No Pre-backup script used ..."
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
    LogMail "File Backup ${RESTIC_TAG} finished successfully."
else
    echo "File Backup failed with Status ${backupRC}"
    LogMail "File Backup failed with Status ${backupRC}"
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
	    LogMail "MariaDB Backup ${RESTIC_TAG} finished successfully."
    else
        echo "MariaDB Failed with Status ${backupRCMariadb}"
	    LogMail "MariaDB Backup ${RESTIC_TAG} failed with Status ${backupRCMariadb}"
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
	    LogMail "Forget ${RESTIC_TAG} finished successfully."
    else
        echo "Forget Failed with Status ${rc}"
	    LogMail "Forget ${RESTIC_TAG} Failed with Status ${rc}."
        restic unlock
        copyErrorLog
    fi
fi

if [ -f "/hooks/post-backup.sh" ]; then
    echo "Starting post-backup script ..."
    /hooks/post-backup.sh $backupRC
else
    echo "No Post-backup script used ..."
fi

end=`date +%s`
echo "--- Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end-start)) seconds ---"
