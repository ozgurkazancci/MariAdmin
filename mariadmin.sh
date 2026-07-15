#!/bin/sh
# MariAdmin - MariaDB/MySQL management menu
# v0.2 - Ozgur Konstantin Kazancci

# ---------------------------------------------------------------------------
# Colors (automatically disabled when stdout is not a terminal)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    ESC=$(printf '\033')
    C_RESET="${ESC}[0m"
    C_TITLE="${ESC}[1;36m"
    C_MENU="${ESC}[0;36m"
    C_KEY="${ESC}[1;33m"
    C_OK="${ESC}[1;32m"
    C_ERR="${ESC}[1;31m"
    C_WARN="${ESC}[1;33m"
    C_PROMPT="${ESC}[1;37m"
    C_DIM="${ESC}[0;90m"
else
    C_RESET=; C_TITLE=; C_MENU=; C_KEY=; C_OK=; C_ERR=; C_WARN=; C_PROMPT=; C_DIM=
fi

say_ok()   { printf '%s%s%s\n' "$C_OK"   "$1" "$C_RESET"; }
say_err()  { printf '%s%s%s\n' "$C_ERR"  "$1" "$C_RESET"; }
say_warn() { printf '%s%s%s\n' "$C_WARN" "$1" "$C_RESET"; }
say_info() { printf '%s%s%s\n' "$C_DIM"  "$1" "$C_RESET"; }

# ---------------------------------------------------------------------------
# Screen helpers: keep the menu at the top and clear between actions so the
# current prompt/output is always shown on a fresh screen.
# ---------------------------------------------------------------------------
clear_screen() {
    [ -t 1 ] || return 0
    command clear 2>/dev/null || printf '%s[H%s[2J' "$ESC" "$ESC"
}

pause() {
    # Only wait for a keypress when running interactively.
    [ -t 0 ] || return 0
    printf '\n%sPress ENTER to continue...%s' "$C_DIM" "$C_RESET"
    read -r _dummy
}

header() {
    clear_screen
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
    printf '%s  MariAdmin - %s%s\n' "$C_TITLE" "$1" "$C_RESET"
    printf '%s==================================================%s\n\n' "$C_TITLE" "$C_RESET"
}

# ---------------------------------------------------------------------------
# Input helpers.
#   ask        : read a visible value; empty ENTER or EOF => return to menu.
#   ask_secret : read a hidden value; empty ENTER or EOF => return to menu.
# Result is placed in REPLY_VAL. Both return non-zero to signal "go back".
# ---------------------------------------------------------------------------
ask() {
    printf '%s%s%s' "$C_PROMPT" "$1" "$C_RESET"
    read -r REPLY_VAL || return 1
    [ -n "$REPLY_VAL" ] || return 1
    return 0
}

ask_secret() {
    printf '%s%s%s' "$C_PROMPT" "$1" "$C_RESET"
    if [ -t 0 ]; then
        stty -echo
        trap 'stty echo' INT
        read -r REPLY_VAL
        _rc=$?
        stty echo
        trap - INT
        printf '\n'
    else
        read -r REPLY_VAL
        _rc=$?
    fi
    [ "$_rc" -eq 0 ] || return 1
    [ -n "$REPLY_VAL" ] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Validation and SQL helpers.
# ---------------------------------------------------------------------------
# Allow only safe identifier characters. This both prevents SQL injection and
# rejects (instead of silently altering) names with spaces or metacharacters.
valid_ident() {
    case "$1" in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Escape backslash and single quote so a value is safe inside a MySQL
# single-quoted string (used for passwords, which may contain any character).
sql_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"
}

# Run a statement as root; on failure the client output is captured in SQL_ERR.
run_sql() {
    SQL_ERR=$(mysql -u root -e "$1" 2>&1)
    return $?
}

print_reason() {
    printf '%s\n' "$1" | sed 's/^/    /'
}

db_exists() {
    _n=$(mysql -u root -N -B -e \
        "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$1';" 2>/dev/null)
    [ "$_n" = "$1" ]
}

user_exists_localhost() {
    _n=$(mysql -u root -N -B -e \
        "SELECT user FROM mysql.user WHERE user='$1' AND host='localhost';" 2>/dev/null)
    [ "$_n" = "$1" ]
}

user_exists_any() {
    _c=$(mysql -u root -N -B -e \
        "SELECT COUNT(*) FROM mysql.user WHERE user='$1';" 2>/dev/null)
    [ -n "$_c" ] && [ "$_c" != "0" ]
}

grant_user_db() {
    _u="$1"; _d="$2"
    if run_sql "GRANT ALL PRIVILEGES ON \`$_d\`.* TO '$_u'@'localhost'; FLUSH PRIVILEGES;"; then
        say_ok "User '$_u' now has access to database '$_d'."
    else
        say_err "Failed to grant privileges:"
        print_reason "$SQL_ERR"
    fi
}

# ---------------------------------------------------------------------------
# Menu actions.
# ---------------------------------------------------------------------------
list_databases() {
    header "Databases"
    mysql -u root -N -B -e "SHOW DATABASES;" 2>/dev/null | while IFS= read -r _db; do
        printf '  %s-%s %s\n' "$C_KEY" "$C_RESET" "$_db"
    done
    pause
}

add_database() {
    header "Add a database"
    ask "Enter new database name (ENTER to return to menu): " || return
    DB_NAME="$REPLY_VAL"

    if ! valid_ident "$DB_NAME"; then
        say_err "Invalid name. Use only letters, digits and underscore."
        pause; return
    fi
    if db_exists "$DB_NAME"; then
        say_err "Database '$DB_NAME' already exists. Choose another name."
        pause; return
    fi

    if run_sql "CREATE DATABASE \`$DB_NAME\`;"; then
        say_ok "Database '$DB_NAME' was created."
    else
        say_err "Database was NOT created. Reason:"
        print_reason "$SQL_ERR"
    fi
    pause
}

remove_database() {
    header "Remove a database"
    ask "Enter database name to remove (ENTER to return to menu): " || return
    DB_NAME="$REPLY_VAL"

    if ! valid_ident "$DB_NAME"; then
        say_err "Invalid name."
        pause; return
    fi
    if ! db_exists "$DB_NAME"; then
        say_err "Database '$DB_NAME' does not exist."
        pause; return
    fi

    printf '%sThis will permanently DROP database "%s". Re-type the name to confirm: %s' \
        "$C_WARN" "$DB_NAME" "$C_RESET"
    read -r CONFIRM || return
    if [ "$CONFIRM" != "$DB_NAME" ]; then
        say_warn "Confirmation did not match. Aborted."
        pause; return
    fi

    if run_sql "DROP DATABASE \`$DB_NAME\`;"; then
        say_ok "Database '$DB_NAME' removed successfully."
    else
        say_err "Failed to remove database:"
        print_reason "$SQL_ERR"
    fi
    pause
}

list_users() {
    header "Users"
    mysql -u root -N -B -e "SELECT CONCAT(user, '@', host) FROM mysql.user;" 2>/dev/null \
        | while IFS= read -r _uh; do
            printf '  %s-%s %s\n' "$C_KEY" "$C_RESET" "$_uh"
        done
    pause
}

add_user() {
    header "Add a user"
    ask "Enter new username (ENTER to return to menu): " || return
    USERNAME="$REPLY_VAL"

    if ! valid_ident "$USERNAME"; then
        say_err "Invalid username. Use only letters, digits and underscore."
        pause; return
    fi
    if user_exists_localhost "$USERNAME"; then
        say_err "User '$USERNAME'@'localhost' already exists. Choose another username."
        pause; return
    fi

    ask_secret "Enter password for new user (ENTER to return to menu): " || return
    PASSWORD="$REPLY_VAL"

    if run_sql "CREATE USER '$USERNAME'@'localhost' IDENTIFIED BY '$(sql_escape "$PASSWORD")';"; then
        say_ok "User '$USERNAME'@'localhost' created successfully."
    else
        say_err "User was NOT created. Reason:"
        print_reason "$SQL_ERR"
        pause; return
    fi

    # Optional database assignment. ENTER (empty) skips the grant.
    ask "Assign this user to a database now? Enter DB name (ENTER to skip): " || { pause; return; }
    DB_NAME="$REPLY_VAL"
    if ! valid_ident "$DB_NAME"; then
        say_err "Invalid database name; skipping grant."
        pause; return
    fi
    if ! db_exists "$DB_NAME"; then
        say_err "Database '$DB_NAME' does not exist; skipping grant."
        pause; return
    fi
    grant_user_db "$USERNAME" "$DB_NAME"
    pause
}

remove_user() {
    header "Remove a user"
    ask "Enter username to remove (ENTER to return to menu): " || return
    USERNAME="$REPLY_VAL"

    if ! valid_ident "$USERNAME"; then
        say_err "Invalid username."
        pause; return
    fi
    if ! user_exists_any "$USERNAME"; then
        say_err "User '$USERNAME' does not exist."
        pause; return
    fi

    say_info "Removing user '$USERNAME' from all hosts..."
    mysql -u root -N -B -e \
        "SELECT CONCAT('DROP USER ', QUOTE(user), '@', QUOTE(host), ';') FROM mysql.user WHERE user='$USERNAME';" \
        2>/dev/null | while IFS= read -r _stmt; do
            [ -n "$_stmt" ] || continue
            mysql -u root -e "$_stmt" >/dev/null 2>&1
        done
    mysql -u root -e "FLUSH PRIVILEGES;" >/dev/null 2>&1

    if user_exists_any "$USERNAME"; then
        say_err "User '$USERNAME' could not be fully removed."
    else
        say_ok "User '$USERNAME' has been removed successfully."
    fi
    pause
}

change_user_password() {
    header "Change user password"
    ask "Enter username whose password you want to change (ENTER to return to menu): " || return
    USERNAME="$REPLY_VAL"

    if ! valid_ident "$USERNAME"; then
        say_err "Invalid username."
        pause; return
    fi
    if ! user_exists_localhost "$USERNAME"; then
        say_err "User '$USERNAME'@'localhost' does not exist."
        pause; return
    fi

    ask_secret "Enter new password for '$USERNAME' (ENTER to return to menu): " || return
    PASSWORD="$REPLY_VAL"

    if run_sql "ALTER USER '$USERNAME'@'localhost' IDENTIFIED BY '$(sql_escape "$PASSWORD")'; FLUSH PRIVILEGES;"; then
        say_ok "Password for '$USERNAME'@'localhost' updated successfully."
    else
        say_err "Failed to update password:"
        print_reason "$SQL_ERR"
    fi
    pause
}

assign_user_to_db() {
    header "Assign a user to a database"
    ask "Enter username to assign (ENTER to return to menu): " || return
    USERNAME="$REPLY_VAL"

    if ! valid_ident "$USERNAME"; then
        say_err "Invalid username."
        pause; return
    fi
    if ! user_exists_localhost "$USERNAME"; then
        say_err "User '$USERNAME'@'localhost' does not exist."
        pause; return
    fi

    ask "Enter the database name to assign (ENTER to return to menu): " || return
    DB_NAME="$REPLY_VAL"

    if ! valid_ident "$DB_NAME"; then
        say_err "Invalid database name."
        pause; return
    fi
    if ! db_exists "$DB_NAME"; then
        say_err "Database '$DB_NAME' does not exist."
        pause; return
    fi

    grant_user_db "$USERNAME" "$DB_NAME"
    pause
}

# ---------------------------------------------------------------------------
# Authentication: use passwordless access when available (unix_socket auth or
# a client defaults file); otherwise prompt for the root password and verify.
# ---------------------------------------------------------------------------
authenticate() {
    if mysql -u root -e 'SELECT 1;' >/dev/null 2>&1; then
        return 0
    fi
    clear_screen
    printf '%sMariAdmin%s\n\n' "$C_TITLE" "$C_RESET"
    ask_secret "Enter MySQL root password: " || {
        say_err "No password entered. Exiting."
        exit 1
    }
    # Hand the password to the client via the environment (kept off the
    # command line and out of the process list).
    export MYSQL_PWD="$REPLY_VAL"
    if ! mysql -u root -e 'SELECT 1;' >/dev/null 2>&1; then
        say_err "Cannot authenticate to MariaDB with that password."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Entry point.
# ---------------------------------------------------------------------------
if ! command -v mysql >/dev/null 2>&1; then
    printf 'Error: the mysql client was not found in PATH.\n' >&2
    exit 1
fi

authenticate

while true; do
    clear_screen
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
    printf '%s  MariAdmin - MariaDB/MySQL Management Menu%s\n' "$C_TITLE" "$C_RESET"
    printf '%s        v0.2 - Ozgur Konstantin Kazancci%s\n' "$C_TITLE" "$C_RESET"
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
    printf '  %s1%s) List databases\n'      "$C_KEY" "$C_RESET"
    printf '  %s2%s) Add a database\n'      "$C_KEY" "$C_RESET"
    printf '  %s3%s) Remove a database\n'   "$C_KEY" "$C_RESET"
    printf '  %s4%s) List users\n'          "$C_KEY" "$C_RESET"
    printf '  %s5%s) Add a user\n'          "$C_KEY" "$C_RESET"
    printf '  %s6%s) Remove a user\n'       "$C_KEY" "$C_RESET"
    printf '  %s7%s) Assign a user to a DB\n' "$C_KEY" "$C_RESET"
    printf '  %s8%s) Change user password\n' "$C_KEY" "$C_RESET"
    printf '  %s9%s) Exit\n'                "$C_KEY" "$C_RESET"
    printf '%s--------------------------------------------------%s\n' "$C_MENU" "$C_RESET"
    printf '%sChoose an option: %s' "$C_PROMPT" "$C_RESET"

    if ! read -r OPTION; then
        printf '\n'
        exit 0
    fi

    case "$OPTION" in
        1) list_databases ;;
        2) add_database ;;
        3) remove_database ;;
        4) list_users ;;
        5) add_user ;;
        6) remove_user ;;
        7) assign_user_to_db ;;
        8) change_user_password ;;
        9) clear_screen; exit 0 ;;
        "") : ;;
        *) say_err "Invalid option. Try again."; pause ;;
    esac
done
