#!/bin/bash

# Original Source: https://borgbackup.readthedocs.io/en/stable/quickstart.html

# 1. Run backup
# 2. Run prune
# 3. List all archives
# 4. List info on most recent archive
# 5. List files in most recent archive
# 6. Send email with backup results

ARCHIVE_NAME="$(hostname -s)-$(date -Iseconds)"

# Log file to store command output for emailing later
LOG_FILE=$(mktemp)

# some helpers and error handling:
info() {
    printf "\n%s\n%s\n\n" "==> $( date )" "$*" | tee -a ${LOG_FILE}
}
trap "echo $( date ) Backup interrupted >&2 | tee -a ${LOG_FILE}; exit 2" INT TERM

# Check environment variables are set
if [ ! -n "${BORG_REPO}" ]; then
    info "Environment variable BORG_REPO not set"
    exit 1
fi
if [ ! -n "${BORG_PASSPHRASE}" ]; then
    info "Environment variable BORG_PASSPHRASE not set"
    exit 1
fi
if [ ! -n "${BORG_FILELIST}" ]; then
    info "Environment variable FILELIST not set"
    exit 1
fi

###
# Step 1: Run backup
###
info "Starting backup to ${BORG_REPO}::${ARCHIVE_NAME} using ${BORG_FILELIST}"

borg create                     \
    --verbose                   \
    --stats                     \
    --show-rc                   \
    --compression lz4           \
    --lock-wait 600             \
    --exclude-caches            \
    --patterns-from ${BORG_FILELIST} \
    ::${ARCHIVE_NAME} 2>&1 | tee -a ${LOG_FILE}

backup_exit=${PIPESTATUS[0]}

###
# Step 2: Clean up repo
###
info "Pruning repository at ${BORG_REPO}"

borg prune                          \
    --list                          \
    --show-rc                       \
    --keep-daily    7               \
    --keep-weekly   4               \
    --keep-monthly  6               \
2>&1 | tee -a ${LOG_FILE}

prune_exit=${PIPESTATUS[0]}

###
# Step 3: Display archive info
###
info "Getting info for ${BORG_REPO}::${ARCHIVE_NAME}"

borg info ::${ARCHIVE_NAME} 2>&1 | tee -a ${LOG_FILE}

###
# Step 4: Display all available archives on the repo
###
info "All archives currently on ${BORG_REPO}"

borg list 2>&1 | tee -a $LOG_FILE

# List files in the archive
ARCHIVE_FILES=$(mktemp)
borg list --short ::${ARCHIVE_NAME} 2>&1 | xz -9 -T0 > ${ARCHIVE_FILES}

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup and Prune finished successfully"
    email_subject="Backups completed successfully on $(hostname) at $(date)"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup and/or Prune finished with warnings" >&2
    email_subject="WARNING: Backups failed on $(hostname) at $(date)"
else
    info "Backup and/or Prune finished with errors" >&2
    email_subject="WARNING: Backups failed on $(hostname) at $(date)"
fi

###
# Step 6: Run backup
###
if [ -n "${BORG_EMAIL}" ]; then
    if [ -f '/usr/bin/mailx' ]; then
        mailx -s "${email_subject}" -A ${ARCHIVE_FILES} "${BORG_EMAIL}" < ${LOG_FILE}
    elif [ -f '/usr/bin/s-nail' ]; then
        s-nail -s "${email_subject}" -a ${ARCHIVE_FILES} "${BORG_EMAIL}" < ${LOG_FILE}
    fi
fi

# Cleanup
rm ${LOG_FILE} ${ARCHIVE_FILES} >/dev/null 2>&1

exit ${global_exit}
