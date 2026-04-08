#!/bin/sh

# Global variables
date=$(date '+%Y-%m-%d')
port=5432
version=v17-1
username=henninb
script_name="$(basename "$0")"
log_file="calendar-db-backup-${date}.log"
exit_code=0

# Logging function
log_msg() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$log_file"
}

# Error logging function
log_error() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$log_file" >&2
    exit_code=1
}

# Execute command with error handling
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local allow_warnings="${3:-false}"

    log_msg "Starting: $description"
    log_msg "Command: $cmd"

    local output
    local cmd_exit_code

    if [ "$allow_warnings" = "true" ]; then
        output=$(eval "$cmd" 2>&1)
        cmd_exit_code=$?

        if echo "$output" | grep -q "WARNING\|NOTICE"; then
            log_msg "Warnings/notices (non-fatal): $(echo "$output" | grep 'WARNING\|NOTICE' | head -3)"
        fi

        if [ $cmd_exit_code -eq 0 ]; then
            log_msg "SUCCESS: $description completed"
            return 0
        else
            log_error "$description failed with exit code $cmd_exit_code"
            log_error "Output: $output"
            return $cmd_exit_code
        fi
    else
        if eval "$cmd"; then
            log_msg "SUCCESS: $description completed"
            return 0
        else
            cmd_exit_code=$?
            log_error "$description failed with exit code $cmd_exit_code"
            return $cmd_exit_code
        fi
    fi
}

# Cleanup function for failed backups
cleanup_on_failure() {
    log_msg "Cleaning up partial backup files due to failure..."
    if [ -n "$calendar_db_filename" ] && [ -f "$calendar_db_filename" ]; then
        rm -f "$calendar_db_filename" 2>/dev/null
        log_msg "Removed partial backup file: $calendar_db_filename"
    fi
    rm -f categories.csv credit_cards.csv persons.csv events.csv occurrences.csv tasks.csv subtasks.csv 2>/dev/null
    log_msg "Cleanup completed"
}

# Check if file exists and has content
check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    elif [ ! -s "$file" ]; then
        log_error "File is empty: $file"
        return 1
    else
        log_msg "File verified: $file ($(wc -l < "$file") lines)"
        return 0
    fi
}

# Generate unique backup filename with counter to prevent overwriting
generate_unique_filename() {
    local base_name="$1"
    local extension="$2"
    local counter=0
    local filename="${base_name}.${extension}"

    while [ -f "$filename" ]; do
        counter=$((counter + 1))
        filename="${base_name}-${counter}.${extension}"
        if [ $counter -gt 99 ]; then
            log_error "Too many backup files exist (100+), please clean up old backups"
            return 1
        fi
    done

    echo "$filename"
    return 0
}

log_msg "Starting backup script: $script_name"
log_msg "Log file: $log_file"

# Test database connectivity
test_db_connection() {
    local test_server="$1"
    local test_port="$2"
    local test_user="$3"

    log_msg "Testing database connectivity to ${test_server}:${test_port}"

    if ! psql -h "$test_server" -p "$test_port" -U "$test_user" -d calendar_db -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Cannot connect to database at ${test_server}:${test_port} with user ${test_user}"
        log_error "Please check: 1) Server is running 2) Network connectivity 3) Credentials in ~/.pgpass"
        return 1
    else
        log_msg "Database connectivity test successful"
        return 0
    fi
}

if [ "$OS" = "Darwin" ]; then
  server=$(ipconfig getifaddr en0)
else
  server=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
fi

log_msg "Checking command line arguments (received $# arguments)"

if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
  log_error "Invalid number of arguments"
  echo "Usage: $0 [server] [port] [version]"
  echo "$0 192.168.10.25 5432 v18-1"
  exit 1
fi

log_msg "Checking for required dependencies"
if [ ! -x "$(command -v psql)" ]; then
  log_error "psql command not found - please install PostgreSQL client tools"
  exit 2
fi

if [ ! -x "$(command -v pg_dump)" ]; then
  log_error "pg_dump command not found - please install PostgreSQL client tools"
  exit 2
fi

log_msg "All required dependencies found"

log_msg "Processing command line parameters"

if [ -n "$1" ]; then
  server=$1
  log_msg "Server set from argument 1: $server"
fi

if [ -n "$2" ]; then
  port=$2
  log_msg "Port set from argument 2: $port"
fi

if [ -n "$3" ]; then
  version=$3
  log_msg "Version set from argument 3: $version"
fi

log_msg "Final configuration - Server: '$server', Port: '$port', Version: '$version', User: '$username'"

log_msg "Reminder: both dump and restore should be performed using the latest binaries"
log_msg "Example: migrate from version 18.0 to 18.1 - use pg_dump binary for 18.1 to connect to 18.0"

log_msg "Checking for ~/.pgpass file"
if [ ! -f "$HOME/.pgpass" ]; then
  log_error "~/.pgpass file not found. Please create it with the format:"
  echo "${server}:${port}:calendar_db:${username}:your_password"
  echo "Then run: chmod 600 ~/.pgpass"
  exit 1
fi

pgpass_perms=$(stat -c "%a" "$HOME/.pgpass" 2>/dev/null || stat -f "%A" "$HOME/.pgpass" 2>/dev/null)
if [ "$pgpass_perms" != "600" ]; then
    log_error "~/.pgpass file has incorrect permissions ($pgpass_perms). Run: chmod 600 ~/.pgpass"
    exit 1
fi

log_msg "pgpass file found with correct permissions"
export PGPASSFILE="$HOME/.pgpass"

# Test connectivity to source database
if ! test_db_connection "$server" "$port" "$username"; then
    log_error "Failed to connect to source database"
    exit 3
fi

log_msg "Starting main backup process"

# Generate unique filename
log_msg "Generating unique backup filename..."
calendar_db_filename=$(generate_unique_filename "calendar_db-${version}-${date}" "tar")
if [ $? -ne 0 ]; then
    log_error "Failed to generate unique filename for calendar_db backup"
    exit 4
fi

log_msg "Using backup filename: $calendar_db_filename"

# Create main database dump
if ! execute_cmd "pg_dump -h '${server}' -p '${port}' -U '${username}' -F t -d calendar_db > '${calendar_db_filename}'" "Create calendar_db dump"; then
    cleanup_on_failure
    exit 4
fi

if ! check_file "${calendar_db_filename}"; then
    cleanup_on_failure
    exit 4
fi

log_msg "Starting table CSV export process"

# Export categories table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, name, color, icon, description, is_seeded FROM categories ORDER BY id) TO 'categories.csv' CSV HEADER\"" "Export categories table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "categories.csv"; then cleanup_on_failure; exit 5; fi

# Export credit_cards table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, name, issuer, last_four, statement_close_day, grace_period_days, weekend_shift, cycle_days, cycle_reference_date, due_day_same_month, due_day_next_month, annual_fee_month, is_active, created_at, is_seeded FROM credit_cards ORDER BY id) TO 'credit_cards.csv' CSV HEADER\"" "Export credit_cards table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "credit_cards.csv"; then cleanup_on_failure; exit 5; fi

# Export persons table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, name, email FROM persons ORDER BY id) TO 'persons.csv' CSV HEADER\"" "Export persons table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "persons.csv"; then cleanup_on_failure; exit 5; fi

# Export events table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, title, category_id, credit_card_id, rrule, dtstart, dtend_rule, duration_days, description, location, reminder_days, priority, amount, is_active, generates_tasks, gcal_calendar_id, created_at, updated_at, is_seeded FROM events ORDER BY id) TO 'events.csv' CSV HEADER\"" "Export events table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "events.csv"; then cleanup_on_failure; exit 5; fi

# Export occurrences table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, event_id, occurrence_date, status, notes, gcal_event_id, synced_at, created_at FROM occurrences ORDER BY id) TO 'occurrences.csv' CSV HEADER\"" "Export occurrences table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "occurrences.csv"; then cleanup_on_failure; exit 5; fi

# Export tasks table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, occurrence_id, category_id, title, description, status, priority, assignee_id, due_date, estimated_minutes, recurrence, gtask_id, synced_at, parent_task_id, created_at, updated_at FROM tasks ORDER BY id) TO 'tasks.csv' CSV HEADER\"" "Export tasks table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "tasks.csv"; then cleanup_on_failure; exit 5; fi

# Export subtasks table
if ! execute_cmd "psql -h '${server}' -p '${port}' -U '${username}' calendar_db -c \"\\copy (SELECT id, task_id, title, status, due_date, \\\"order\\\", gtask_id, created_at, updated_at FROM subtasks ORDER BY id) TO 'subtasks.csv' CSV HEADER\"" "Export subtasks table"; then
    cleanup_on_failure; exit 5
fi
if ! check_file "subtasks.csv"; then cleanup_on_failure; exit 5; fi

# Copy backup to remote server
log_msg "Copying backup to remote server raspi"
if ! execute_cmd "scp -p '${calendar_db_filename}' raspi:/home/pi/downloads/calendar-db-bkp/" "Copy backup to raspi server"; then
    log_error "Failed to copy backup to remote server, but backup files are available locally"
    exit_code=1
fi

# Final status reporting
log_msg "Backup process completed"
log_msg "Files created:"
log_msg "  - ${calendar_db_filename} ($(ls -lh "${calendar_db_filename}" | awk '{print $5}'))"
log_msg "CSV files exported: $(ls -1 categories.csv credit_cards.csv persons.csv events.csv occurrences.csv tasks.csv subtasks.csv 2>/dev/null | wc -l)/7 tables"

if [ $exit_code -eq 0 ]; then
    log_msg "SUCCESS: All backup operations completed successfully"
else
    log_error "PARTIAL SUCCESS: Some operations failed (check log for details)"
fi

exit $exit_code
