#!/bin/bash

# Backs up root directory using rsync to RSYNC_DEST
# Set RSYNC_EMAIL to a notification email address

# Log file to store command output for emailing later
LOG_FILE=$(mktemp)

# some helpers and error handling:
info() {
    printf "\n%s\n%s\n\n" "==> $( date )" "$*" | tee -a ${LOG_FILE}
}
trap "echo $( date ) Backup interrupted >&2 | tee -a ${LOG_FILE}; exit 2" INT TERM

# Check environment variables are set
if [ ! -n "${RSYNC_DEST}" ]; then
    info "Environment variable RSYNC_DEST not set"
    exit 1
fi

info "Starting backup to ${RSYNC_DEST}"

rsync -aAXv / \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
    ${RSYNC_DEST} 2>&1 | tee -a ${LOG_FILE}

backup_exit=${PIPESTATUS[0]}

if [ ${backup_exit} -eq 0 ]; then
    info "Backup finished successfully"
    email_subject="Backups completed successfully on $(hostname) at $(date)"
elif [ ${backup_exit} -eq 1 ]; then
    info "Backup finished with warnings" >&2
    email_subject="WARNING: Backups failed on $(hostname) at $(date)"
else
    info "Backup and/or Prune finished with errors" >&2
    email_subject="WARNING: Backups failed on $(hostname) at $(date)"
fi

if [ -n "${RSYNC_EMAIL}" ]; then
    mailx -s "${email_subject}" "${RSYNC_EMAIL}" < ${LOG_FILE}
fi

exit ${backup_exit}