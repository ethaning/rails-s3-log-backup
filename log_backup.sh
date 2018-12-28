#!/bin/bash

# Desc: Back up large log files to S3
# Author: Ethaning

# Ensures that large log files are backed up to S3 bucket
# Task should be run by cron at regular intervals

# ENV Variables required:
# - RAILS_ROOT : path to root of rails repo
# - AWS_S3_LOG_BACKUPS_BUCKET : name of the S3 bucket; the location where the
#   backups will be sent to

format_date () {
  echo $(date '+%Y-%m-%d %H:%M:%S.%3N')
}

timestamp_file() {
  if [ "$#" -ne 1 ]; then
    echo "Illegal number of arguments. Only accepts 1 argument"
    exit 1
  fi

  filename=${1%.txt}
  ext=${1#"$filename"}
  mv $1 "${filename}-$(date '+%Y-%m-%d-%H-%M-%S')${ext}"
}

# Check that the required ENV variables exist
[[ ! -z $AWS_S3_LOG_BACKUPS_BUCKET ]] || { echo '$AWS_S3_LOG_BACKUPS_BUCKET is not set' >&2; exit 3; }
[[ ! -z $RAILS_ROOT ]] || { echo '$RAILS_ROOT is not set' >&2; exit 3; }

echo "$(format_date): Initializing log backup script"

# Set log directories
declare -r log_dir="${RAILS_ROOT}/log"
declare -r temp_log_dir="${RAILS_ROOT}/logs_tmp"

# Set S3 bucket name
declare -r bucket_name="${AWS_S3_LOG_BACKUPS_BUCKET}"

# Set max log file size to 50MB
declare -r max_file_size="50M"

# Check log dir exists
if [[ ! -d $log_dir ]]; then
  echo '$log_dir has not been set correctly' >&2
  exit 1
fi

# Check temp log dir exists and is empty; if not, then create
if [[ -d $temp_log_dir ]]; then
  if [[ ! -z "$(ls -A ${temp_log_dir}/)" ]]; then
    echo "${temp_log_dir} is not empty. Cannot proceed" >&2
    exit 2
  fi
else
  mkdir $temp_log_dir
fi

# Make note of any log files with filesize > $max_file_size
declare files=""
files=$(find "${log_dir}/" -type f -size +${max_file_size})

# Exit script early if there are no log files larger than the max file size
if [[ ! $files ]]; then
  echo "$(format_date): No log files in ${log_dir} larger than ${max_file_size}!" >&2
  exit 0
fi

# Copy files to temp_log_dir and reset file in log_dir
# cp $files $temp_log_dir
for f in $files; do
  cp $f $temp_log_dir
  > $f
done

# rename temp_log_dir files to end with timestamp
files=$(ls -d $temp_log_dir/*)

for f in $files; do
  timestamp_file $f
done

# move temp_log_dir files to S3 bucket
aws s3 mv $temp_log_dir "${bucket_name}/log_backups" --recursive --include '*' >&2

# remove temp log dir
rm -r $temp_log_dir

# Print report of backup script, having backed up files.
echo "Backup Succesful!"
echo "Files backed up:"
for f in $files; do
  echo "${f##/*/}"
done

exit 0
