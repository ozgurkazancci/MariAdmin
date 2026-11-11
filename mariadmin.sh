#!/bin/sh
# MariAdmin - MariaDB/MySQL management menu
# v0.4 - Ozgur Konstantin Kazancci

VERSION=0.4
TTY_STATE=
DB_TEMP_DIR=
if [ -t 1 ]; then
    ESC=$(printf '\033')
    C_RESET="${ESC}[0m"; C_TITLE="${ESC}[1;36m"; C_MENU="${ESC}[0;36m"
    C_KEY="${ESC}[1;33m"; C_OK="${ESC}[1;32m"; C_ERR="${ESC}[1;31m"
    C_WARN="${ESC}[1;33m"; C_PROMPT="${ESC}[1;37m"; C_DIM="${ESC}[0;90m"
    C_INFO="${ESC}[1;32m"
else
    C_RESET=; C_TITLE=; C_MENU=; C_KEY=; C_OK=; C_ERR=; C_WARN=; C_PROMPT=; C_DIM=
    C_INFO=
fi
say_ok()   { printf '%s%s%s\n' "$C_OK" "$1" "$C_RESET"; }
say_err()  { printf '%s%s%s\n' "$C_ERR" "$1" "$C_RESET"; }
say_warn() { printf '%s%s%s\n' "$C_WARN" "$1" "$C_RESET"; }
say_info() { printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
clear_screen() {
    [ -t 1 ] || return 0
    command clear 2>/dev/null || printf '%s[H%s[2J' "$ESC" "$ESC"
}
pause() {
    [ -t 0 ] || return 0
    printf '\n%sPress ENTER to continue...%s' "$C_DIM" "$C_RESET"
    IFS= read -r _dummy || :
}
connection_info() {
    if [ "$DB_PROTOCOL" = socket ]; then
        printf '%s%s%s\n' "$C_INFO" "Connection: localhost via socket ${DB_SOCKET:-default}" "$C_RESET"
    else
        printf '%s%s%s\n' "$C_INFO" "Connection: $DB_HOST:$DB_PORT (TCP)" "$C_RESET"
    fi
    if [ -n "${DB_CURRENT_USER-}" ]; then
        printf '%s%s%s\n' "$C_INFO" "Server: $DB_SERVER_HOST:$DB_SERVER_PORT | Account: $DB_CURRENT_USER" "$C_RESET"
    fi
    if [ -n "${DB_SOFTWARE-}" ]; then
        printf '%s%s%s\n' "$C_INFO" "Software: $DB_SOFTWARE" "$C_RESET"
    fi
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
}
header() {
    clear_screen
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
    printf '%s  MariAdmin - %s%s\n' "$C_TITLE" "$1" "$C_RESET"
    printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
    connection_info
    printf '\n'
}
restore_terminal() {
    if [ -n "$TTY_STATE" ]; then
        stty "$TTY_STATE" 2>/dev/null || :
        TTY_STATE=
    fi
}
cleanup() {
    restore_terminal
    unset REPLY_VAL PASSWORD MYSQL_PWD
    if [ -n "$DB_TEMP_DIR" ]; then
        rm -f "$DB_TEMP_DIR/client.cnf" "$DB_TEMP_DIR/client.cnf.new" "$DB_TEMP_DIR/sql-error"
        rmdir "$DB_TEMP_DIR" 2>/dev/null || :
        DB_TEMP_DIR=
    fi
}
ask() {
    printf '%s%s%s' "$C_PROMPT" "$1" "$C_RESET"
    IFS= read -r REPLY_VAL || return 1
    [ -n "$REPLY_VAL" ]
}
ask_secret() {
    unset REPLY_VAL
    printf '%s%s%s' "$C_PROMPT" "$1" "$C_RESET"
    if [ -t 0 ]; then
        TTY_STATE=$(stty -g) || { say_err 'Cannot read terminal settings.'; return 1; }
        if ! stty -echo; then
            restore_terminal
            say_err 'Cannot hide password input.'
            return 1
        fi
        if IFS= read -r REPLY_VAL; then _read_rc=0; else _read_rc=$?; fi
        restore_terminal
        printf '\n'
    else
        if IFS= read -r REPLY_VAL; then _read_rc=0; else _read_rc=$?; fi
    fi
    [ "$_read_rc" -eq 0 ] && [ -n "$REPLY_VAL" ]
}
valid_ident() {
    case "$1" in ''|*[!A-Za-z0-9_]*) return 1 ;; *) return 0 ;; esac
}
# Usernames are entered without the host part; MariAdmin always works on
# 'localhost' (Remove a user drops every host entry of that username).
valid_username() {
    case "$1" in
        *@*)
            say_err "Enter only the username, without '@host' (e.g. 'webuser', not 'webuser@localhost')."
            return 1 ;;
    esac
    if ! valid_ident "$1"; then
        say_err 'Invalid username. Use only letters, digits and underscore.'
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# SQL and connection helpers. SQL is sent on stdin, never as a client argument.
# All connections remove only NO_BACKSLASH_ESCAPES from their own session mode.
# ---------------------------------------------------------------------------
sql_escape() (
    _text=$1
    _cr=$(printf '\r'); _tab=$(printf '\t'); _bs=$(printf '\b')
    _nl='
'
    while [ -n "$_text" ]; do
        _rest=${_text#?}
        _char=${_text%"$_rest"}
        case "$_char" in
            '\') printf '%s' '\\' ;;
            "'") printf '%s' "\\'" ;;
            "$_cr") printf '%s' '\r' ;;
            "$_tab") printf '%s' '\t' ;;
            "$_bs") printf '%s' '\b' ;;
            "$_nl") printf '%s' '\n' ;;
            *) printf '%s' "$_char" ;;
        esac
        _text=$_rest
    done
)

# Client option files have their own escaping rules, independent of SQL modes.
option_escape() (
    _text=$1
    _cr=$(printf '\r'); _tab=$(printf '\t'); _bs=$(printf '\b')
    _nl='
'
    while [ -n "$_text" ]; do
        _rest=${_text#?}
        _char=${_text%"$_rest"}
        case "$_char" in
            '\') printf '%s' '\\' ;;
            '"') printf '%s' '\"' ;;
            "$_cr") printf '%s' '\r' ;;
            "$_tab") printf '%s' '\t' ;;
            "$_bs") printf '%s' '\b' ;;
            "$_nl") printf '%s' '\n' ;;
            *) printf '%s' "$_char" ;;
        esac
        _text=$_rest
    done
)

set_auth_password() {
    # The parent directory is private; use an atomic replacement for rotation.
    if ! (
        umask 077
        {
            printf '[client]\npassword="'
            option_escape "$1"
            printf '"\n'
        } > "$DB_TEMP_DIR/client.cnf.new" &&
        chmod 600 "$DB_TEMP_DIR/client.cnf.new" &&
        mv -f "$DB_TEMP_DIR/client.cnf.new" "$DB_TEMP_DIR/client.cnf"
    ); then
        SQL_ERR='Cannot securely store the database credential.'
        return 1
    fi
    DB_AUTH_FILE="$DB_TEMP_DIR/client.cnf"
}

prepare_auth() {
    # Unset first so a same-named inherited variable cannot remain exported.
    unset DB_AUTH_PASSWORD
    DB_AUTH_PASSWORD=${MYSQL_PWD-}
    DB_INHERITED_PASSWORD_SET=${MYSQL_PWD+x}
    unset MYSQL_PWD
    DB_AUTH_FILE=
    DB_CURRENT_USER=
    DB_CURRENT_ACCOUNT_HEX=
    DB_TEMP_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/mariadmin.XXXXXXXXXX") || {
        unset DB_AUTH_PASSWORD
        SQL_ERR='Cannot create a private directory for database credentials.'
        return 1
    }
    if ! chmod 700 "$DB_TEMP_DIR"; then
        unset DB_AUTH_PASSWORD
        SQL_ERR='Cannot secure the database credential directory.'
        return 1
    fi
    if [ "$DB_INHERITED_PASSWORD_SET" = x ]; then
        if ! set_auth_password "$DB_AUTH_PASSWORD"; then
            unset DB_AUTH_PASSWORD
            return 1
        fi
    fi
    unset DB_AUTH_PASSWORD DB_INHERITED_PASSWORD_SET
}

db_client_call() {
    set -- "$DB_CLIENT"
    # --defaults-file must be the first option. It overrides stale passwords
    # in ~/.my.cnf after a password is supplied, including on password rotation.
    if [ -n "$DB_AUTH_FILE" ]; then
        set -- "$@" "--defaults-file=$DB_AUTH_FILE"
    fi
    set -- "$@" "--user=$DB_ADMIN" "--host=$DB_HOST" "--port=$DB_PORT" \
        "--protocol=$DB_PROTOCOL" --connect-timeout=10 \
        --batch --raw --skip-column-names --binary-mode --skip-reconnect \
        --skip-force --default-character-set=utf8mb4
    if [ -n "$DB_SOCKET" ]; then
        set -- "$@" "--socket=$DB_SOCKET"
    fi
    if [ -n "$DB_AUTH_FILE" ]; then
        # MySQL reads .mylogin.cnf even with --defaults-file. This documented
        # override also works with MySQL versions before --no-login-paths.
        MYSQL_TEST_LOGIN_FILE="$DB_TEMP_DIR/no-login.cnf" "$@"
    else
        "$@"
    fi
}

query_sql() {
    SQL_OUT=
    SQL_ERR=
    _query_secret=${2-}
    if ! (umask 077; : > "$DB_TEMP_DIR/sql-error"); then
        SQL_ERR='Cannot create a private database error buffer.'
        return 1
    fi
    SQL_OUT=$(
        {
            printf '%s\n' "SET SESSION sql_mode = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', @@SESSION.sql_mode, ','), ',NO_BACKSLASH_ESCAPES,', ','));"
            printf '%s\n' "$1"
        } | db_client_call 2> "$DB_TEMP_DIR/sql-error"
    )
    _query_rc=$?
    if [ "$_query_rc" -ne 0 ]; then
        # Clients may echo the complete failing statement, including passwords.
        # Only a numeric server error code is safe to retain or display.
        _query_code=$(LC_ALL=C sed -n 's/^ERROR \([0-9][0-9]*\).*/\1/p' \
            "$DB_TEMP_DIR/sql-error" | head -n 1)
        if [ -n "$_query_code" ]; then
            SQL_ERR="Database request failed (ERROR $_query_code)."
        else
            SQL_ERR="Database client failed (exit status $_query_rc). Check the connection and client options."
        fi
        SQL_OUT=
    fi
    if [ "$_query_secret" = secret ]; then
        SQL_OUT=
    fi
    : > "$DB_TEMP_DIR/sql-error"
    return "$_query_rc"
}

run_sql() {
    query_sql "$1" "${2-}"
}

print_reason() {
    printf '%s\n' "$1" | sed 's/^/    /'
}

# Existence checks are tri-state: 0 = present, 1 = absent, 2 = query failure.
check_count_result() {
    case "$SQL_OUT" in
        0) return 1 ;;
        ''|*[!0-9]*) SQL_ERR='The server returned an invalid existence result.'; return 2 ;;
        *) return 0 ;;
    esac
}

db_exists() {
    query_sql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$(sql_escape "$1")';" || return 2
    check_count_result
}

user_exists_localhost() {
    query_sql "SELECT COUNT(*) FROM mysql.user WHERE user='$(sql_escape "$1")' AND host='localhost';" || return 2
    check_count_result
}

user_exists_any() {
    query_sql "SELECT COUNT(*) FROM mysql.user WHERE user='$(sql_escape "$1")';" || return 2
    check_count_result
}

# Turn VERSION() and @@version_comment into e.g. "MariaDB 10.6.27" or "MySQL 8.0.36".
software_label() {
    _sw_version=${1%%-*}
    case "$1" in
        *MariaDB*|*mariadb*) _sw_name=MariaDB ;;
        *)
            case "$2" in
                *Percona*) _sw_name='Percona Server' ;;
                *) _sw_name=MySQL ;;
            esac ;;
    esac
    printf '%s %s' "$_sw_name" "$_sw_version"
}

verify_connection() {
    # Never-empty columns come first: tab is IFS whitespace, so an empty field
    # would be collapsed by read and shift every following value.
    query_sql "SELECT CURRENT_USER(), HEX(CURRENT_USER()), VERSION(), COALESCE(NULLIF(@@version_comment, ''), '-'), @@hostname, @@port, @@socket;" || return 1
    _previous_account=$DB_CURRENT_ACCOUNT_HEX
    IFS="$(printf '\t')" read -r _account _account_hex _server_version _server_comment _server_host _server_port _server_socket <<EOF
$SQL_OUT
EOF
    case "$_account_hex" in
        ''|*[!0-9A-Fa-f]*) SQL_ERR='The server returned an invalid account identity.'; return 1 ;;
    esac
    if [ -n "$_previous_account" ] && [ "$_previous_account" != "$_account_hex" ]; then
        SQL_ERR='The authenticated account changed unexpectedly. Reconnect before continuing.'
        return 1
    fi
    DB_CURRENT_USER=$_account
    DB_CURRENT_ACCOUNT_HEX=$_account_hex
    DB_SERVER_HOST=$_server_host
    DB_SERVER_PORT=$_server_port
    DB_SERVER_SOCKET=$_server_socket
    DB_SOFTWARE=$(software_label "$_server_version" "$_server_comment")
    # Keep a custom default socket available when a password file replaces the
    # normal client defaults. An explicitly selected socket always takes priority.
    if [ "$DB_PROTOCOL" = socket ] && [ -z "$DB_SOCKET" ]; then
        DB_SOCKET=$DB_SERVER_SOCKET
    fi
    return 0
}

authenticate() {
    if verify_connection; then
        return 0
    fi
    clear_screen
    printf '%sMariAdmin%s\n\n' "$C_TITLE" "$C_RESET"
    ask_secret "Enter password for database administrator '$DB_ADMIN': " || {
        say_err 'No password entered. Exiting.'
        return 1
    }
    if ! set_auth_password "$REPLY_VAL"; then
        unset REPLY_VAL
        say_err "$SQL_ERR"
        return 1
    fi
    unset REPLY_VAL
    if ! verify_connection; then
        say_err "Cannot authenticate as '$DB_ADMIN' on the selected server."
        print_reason "$SQL_ERR"
        return 1
    fi
    return 0
}

grant_user_db() {
    _grant_user=$1
    _grant_db=$2
    # MariaDB has no partial_revokes variable and returns an empty result.
    # MySQL with partial_revokes=ON treats database identifiers literally.
    if ! query_sql "SHOW VARIABLES LIKE 'partial_revokes';"; then
        say_err 'Cannot determine database privilege matching rules.'
        print_reason "$SQL_ERR"
        return 1
    fi
    _partial_revokes=${SQL_OUT##*"$(printf '\t')"}
    case "$_partial_revokes" in
        ON|on|1) _grant_pattern=$_grant_db ;;
        OFF|off|0|'') _grant_pattern=$(printf '%s' "$_grant_db" | sed 's/_/\\_/g') ;;
        *) say_err 'Unknown database privilege matching rules; grant was not applied.'; return 1 ;;
    esac
    if run_sql "GRANT ALL PRIVILEGES ON \`$_grant_pattern\`.* TO '$(sql_escape "$_grant_user")'@'localhost';"; then
        say_ok "User '$_grant_user' now has access to database '$_grant_db'."
        return 0
    fi
    say_err 'Failed to grant privileges:'
    print_reason "$SQL_ERR"
    return 1
}


# ---------------------------------------------------------------------------
# Menu actions. A failed lookup is never treated as a missing account/schema.
# ---------------------------------------------------------------------------
require_database() {
    if db_exists "$1"; then return 0; else _lookup_rc=$?; fi
    if [ "$_lookup_rc" -eq 1 ]; then
        say_err "Database '$1' does not exist."
    else
        say_err 'Cannot check whether the database exists.'
        print_reason "$SQL_ERR"
    fi
    return 1
}
require_local_user() {
    if user_exists_localhost "$1"; then return 0; else _lookup_rc=$?; fi
    if [ "$_lookup_rc" -eq 1 ]; then
        say_err "User '$1'@'localhost' does not exist."
    else
        say_err 'Cannot check whether the user exists.'
        print_reason "$SQL_ERR"
    fi
    return 1
}
list_databases() {
    header 'Databases'
    if query_sql 'SHOW DATABASES;'; then
        if [ -n "$SQL_OUT" ]; then printf '%s\n' "$SQL_OUT" | sed 's/^/  - /'; fi
    else
        say_err 'Cannot list databases.'; print_reason "$SQL_ERR"
    fi
    pause
}
print_user_list() {
    if query_sql "SELECT CONCAT(user, '@', host) FROM mysql.user ORDER BY user, host;"; then
        if [ -n "$SQL_OUT" ]; then printf '%s\n' "$SQL_OUT" | sed 's/^/  - /'; else say_info '  (no users found)'; fi
        return 0
    fi
    say_err 'Cannot list users.'; print_reason "$SQL_ERR"
    return 1
}
list_users() {
    header 'Users'
    print_user_list
    pause
}
add_database() {
    header 'Add a database'
    ask 'Enter new database name (ENTER to return to menu): ' || return
    DB_NAME=$REPLY_VAL
    if ! valid_ident "$DB_NAME" || [ "${#DB_NAME}" -gt 64 ]; then
        say_err 'Invalid name. Use 1-64 letters, digits or underscores.'; pause; return
    fi
    if db_exists "$DB_NAME"; then
        say_err "Database '$DB_NAME' already exists."; pause; return
    else
        _lookup_rc=$?
        if [ "$_lookup_rc" -ne 1 ]; then
            say_err 'Cannot check whether the database exists.'; print_reason "$SQL_ERR"; pause; return
        fi
    fi
    if run_sql "CREATE DATABASE \`$DB_NAME\`;"; then
        say_ok "Database '$DB_NAME' was created."
    else
        say_err 'Database was NOT created.'; print_reason "$SQL_ERR"
    fi
    pause
}
remove_database() {
    header 'Remove a database'
    ask 'Enter database name to remove (ENTER to return to menu): ' || return
    DB_NAME=$REPLY_VAL
    if ! valid_ident "$DB_NAME"; then say_err 'Invalid name.'; pause; return; fi
    require_database "$DB_NAME" || { pause; return; }
    printf '%sThis will permanently DROP database "%s". Re-type the name to confirm: %s' "$C_WARN" "$DB_NAME" "$C_RESET"
    IFS= read -r CONFIRM || return
    if [ "$CONFIRM" != "$DB_NAME" ]; then say_warn 'Confirmation did not match. Aborted.'; pause; return; fi
    if run_sql "DROP DATABASE \`$DB_NAME\`;"; then
        say_ok "Database '$DB_NAME' removed successfully."
    else
        say_err 'Failed to remove database.'; print_reason "$SQL_ERR"
    fi
    pause
}
add_user() {
    header 'Add a user'
    ask 'Enter new username (ENTER to return to menu): ' || return
    USERNAME=$REPLY_VAL
    valid_username "$USERNAME" || { pause; return; }
    if user_exists_localhost "$USERNAME"; then
        say_err "User '$USERNAME'@'localhost' already exists."; pause; return
    else
        _lookup_rc=$?
        if [ "$_lookup_rc" -ne 1 ]; then
            say_err 'Cannot check whether the user exists.'; print_reason "$SQL_ERR"; pause; return
        fi
    fi
    ask_secret 'Enter password for new user (ENTER to return to menu): ' || return
    if run_sql "CREATE USER '$USERNAME'@'localhost' IDENTIFIED BY '$(sql_escape "$REPLY_VAL")';" secret; then
        unset REPLY_VAL
        say_ok "User '$USERNAME'@'localhost' created successfully."
    else
        unset REPLY_VAL
        say_err 'User was NOT created.'; print_reason "$SQL_ERR"; pause; return
    fi
    ask 'Assign this user to a database now? Enter DB name (ENTER to skip): ' || { pause; return; }
    DB_NAME=$REPLY_VAL
    if ! valid_ident "$DB_NAME"; then say_err 'Invalid database name; skipping grant.'; pause; return; fi
    require_database "$DB_NAME" || { pause; return; }
    grant_user_db "$USERNAME" "$DB_NAME"
    pause
}
remove_user() {
    header 'Remove a user'
    printf '%sExisting users:%s\n' "$C_TITLE" "$C_RESET"
    print_user_list
    printf '\n%sEnter only the username, without the @host part.%s\n' "$C_KEY" "$C_RESET"
    printf '%sExample: to remove webuser@localhost, type: webuser%s\n\n' "$C_KEY" "$C_RESET"
    ask 'Enter username to remove (ENTER to return to menu): ' || return
    USERNAME=$REPLY_VAL
    valid_username "$USERNAME" || { pause; return; }
    if ! verify_connection; then
        say_err 'Cannot verify the active administrator.'; print_reason "$SQL_ERR"; pause; return
    fi
    if [ "$USERNAME" = "${DB_CURRENT_USER%@*}" ]; then
        say_err 'Cannot remove the active administrator. Connect using a different administrator first.'
        pause; return
    fi
    # Build the account list without GROUP_CONCAT (which can silently truncate).
    # --raw keeps QUOTE(host) unchanged; one DROP statement uses one connection.
    if ! query_sql "SELECT CONCAT(QUOTE(user), '@', REPLACE(QUOTE(host), CHAR(10), CONCAT(CHAR(92), 'n'))) FROM mysql.user WHERE user='$USERNAME' ORDER BY host;"; then
        say_err 'Cannot retrieve the accounts to remove.'; print_reason "$SQL_ERR"; pause; return
    fi
    if [ -z "$SQL_OUT" ]; then say_err "User '$USERNAME' does not exist."; pause; return; fi
    _drop_accounts=
    while IFS= read -r _account; do
        [ -n "$_account" ] || continue
        if [ -n "$_drop_accounts" ]; then _drop_accounts="$_drop_accounts, $_account"; else _drop_accounts=$_account; fi
    done <<EOF
$SQL_OUT
EOF
    printf '%sThis will remove "%s" from ALL hosts. Re-type the username to confirm: %s' "$C_WARN" "$USERNAME" "$C_RESET"
    IFS= read -r CONFIRM || return
    if [ "$CONFIRM" != "$USERNAME" ]; then say_warn 'Confirmation did not match. Aborted.'; pause; return; fi
    if ! run_sql "DROP USER $_drop_accounts;"; then
        say_err 'User removal failed; some host accounts may remain.'; print_reason "$SQL_ERR"; pause; return
    fi
    if user_exists_any "$USERNAME"; then
        say_err "User '$USERNAME' could not be fully removed."
    else
        _lookup_rc=$?
        if [ "$_lookup_rc" -eq 1 ]; then
            say_ok "User '$USERNAME' has been removed successfully."
        else
            say_err 'Removal ran, but the result could not be verified.'; print_reason "$SQL_ERR"
        fi
    fi
    pause
}
change_user_password() {
    header 'Change user password'
    ask 'Enter username whose password you want to change (ENTER to return to menu): ' || return
    USERNAME=$REPLY_VAL
    valid_username "$USERNAME" || { pause; return; }
    require_local_user "$USERNAME" || { pause; return; }
    if ! verify_connection || ! query_sql 'SELECT VERSION();'; then
        say_err 'Cannot verify the server and administrator.'; print_reason "$SQL_ERR"; pause; return
    fi
    case "$SQL_OUT" in *MariaDB*) _password_style=mariadb ;; *) _password_style=mysql ;; esac
    ask_secret "Enter new password for '$USERNAME' (ENTER to return to menu): " || return
    # SET PASSWORD preserves MariaDB authentication plugins such as unix_socket.
    if [ "$_password_style" = mariadb ]; then
        _password_sql="SET PASSWORD FOR '$USERNAME'@'localhost' = PASSWORD('$(sql_escape "$REPLY_VAL")');"
    else
        _password_sql="ALTER USER '$USERNAME'@'localhost' IDENTIFIED BY '$(sql_escape "$REPLY_VAL")';"
    fi
    if run_sql "$_password_sql" secret; then
        unset _password_sql
        if [ "$DB_CURRENT_USER" = "$USERNAME@localhost" ]; then
            if ! set_auth_password "$REPLY_VAL" || ! verify_connection; then
                unset REPLY_VAL
                say_err 'Password changed, but reconnecting failed. Restart MariAdmin with the new password.'
                print_reason "$SQL_ERR"
                exit 1
            fi
        fi
        unset REPLY_VAL
        say_ok "Password for '$USERNAME'@'localhost' updated successfully."
    else
        unset REPLY_VAL _password_sql
        say_err 'Failed to update password.'; print_reason "$SQL_ERR"
    fi
    pause
}
assign_user_to_db() {
    header 'Assign a user to a database'
    ask 'Enter username to assign (ENTER to return to menu): ' || return
    USERNAME=$REPLY_VAL
    valid_username "$USERNAME" || { pause; return; }
    require_local_user "$USERNAME" || { pause; return; }
    ask 'Enter the database name to assign (ENTER to return to menu): ' || return
    DB_NAME=$REPLY_VAL
    if ! valid_ident "$DB_NAME"; then say_err 'Invalid database name.'; pause; return; fi
    require_database "$DB_NAME" || { pause; return; }
    grant_user_db "$USERNAME" "$DB_NAME"
    pause
}
usage() {
    printf '%s\n' "MariAdmin v$VERSION - local MariaDB/MySQL administration" \
        'Usage: sh mariadmin.sh [--user NAME] [--socket PATH | --host HOST [--port PORT]]' \
        '  --user NAME    Administrator account (default: root)' \
        '  --socket PATH  Local Unix socket (default: client socket)' \
        '  --host HOST    Local TCP host: localhost, 127.0.0.1 or ::1' \
        '  --port PORT    Local TCP port (default: 3306)' \
        '  --help         Show this help' \
        '  --version      Show the version'
}
select_client() {
    if command -v mariadb >/dev/null 2>&1; then DB_CLIENT=mariadb
    elif command -v mysql >/dev/null 2>&1; then DB_CLIENT=mysql
    else say_err 'Error: neither mariadb nor mysql was found in PATH.'; return 1
    fi
}
parse_options() {
    _tcp_selected=0; _socket_selected=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) usage; return 2 ;;
            --version|-V) printf '%s\n' "$VERSION"; return 2 ;;
            --user|--host|--port|--socket)
                if [ "$#" -lt 2 ] || [ -z "$2" ]; then say_err "Missing value for $1."; return 1; fi
                case "$1" in
                    --user) DB_ADMIN=$2 ;;
                    --host) DB_HOST=$2; _tcp_selected=1 ;;
                    --port) DB_PORT=$2; _tcp_selected=1 ;;
                    --socket) DB_SOCKET=$2; _socket_selected=1 ;;
                esac
                shift 2 ;;
            *) say_err "Unknown option: $1"; usage; return 1 ;;
        esac
    done
    if [ "$_tcp_selected" -eq 1 ] && [ "$_socket_selected" -eq 1 ]; then
        say_err 'Use --socket or TCP options, not both.'; return 1
    fi
    case "$DB_HOST" in localhost|127.0.0.1|::1) : ;; *) say_err 'Only local database servers are supported.'; return 1 ;; esac
    case "$DB_PORT" in ''|*[!0-9]*|0*) say_err 'Invalid TCP port.'; return 1 ;; esac
    if [ "${#DB_PORT}" -gt 5 ] || [ "$DB_PORT" -gt 65535 ]; then say_err 'Invalid TCP port.'; return 1; fi
    if [ "$_tcp_selected" -eq 1 ]; then DB_PROTOCOL=tcp; fi
    return 0
}
main() {
    DB_ADMIN=root; DB_HOST=localhost; DB_PORT=3306; DB_SOCKET=; DB_PROTOCOL=socket
    DB_TEMP_DIR=; DB_CURRENT_USER=; DB_SOFTWARE=
    unset PASSWORD REPLY_VAL SQL_OUT SQL_ERR _password_sql
    if parse_options "$@"; then :; else _parse_rc=$?; [ "$_parse_rc" -eq 2 ] && return 0; return 1; fi
    select_client || return 1
    trap 'cleanup' 0
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    if ! prepare_auth; then say_err "$SQL_ERR"; return 1; fi
    connection_info
    authenticate || return 1
    while true; do
        clear_screen
        printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
        printf '%s  MariAdmin - MariaDB/MySQL Management Menu%s\n' "$C_TITLE" "$C_RESET"
        printf '%s        v%s - Ozgur Konstantin Kazancci%s\n' "$C_TITLE" "$VERSION" "$C_RESET"
        printf '%s==================================================%s\n' "$C_TITLE" "$C_RESET"
        connection_info
        printf '%s\n' '  1) List databases' '  2) Add a database' '  3) Remove a database' \
            '  4) List users' '  5) Add a user' '  6) Remove a user' \
            '  7) Assign a user to a DB' '  8) Change user password' '  9) Exit'
        printf '%s--------------------------------------------------%s\n' "$C_MENU" "$C_RESET"
        printf '%sChoose an option: %s' "$C_PROMPT" "$C_RESET"
        if ! IFS= read -r OPTION; then printf '\n'; return 0; fi
        case "$OPTION" in
            1) list_databases ;; 2) add_database ;; 3) remove_database ;;
            4) list_users ;; 5) add_user ;; 6) remove_user ;;
            7) assign_user_to_db ;; 8) change_user_password ;;
            9) clear_screen; return 0 ;;
            '') : ;; *) say_err 'Invalid option. Try again.'; pause ;;
        esac
    done
}
main "$@"
