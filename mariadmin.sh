#!/bin/sh

# Prompt for MySQL root password securely (OpenBSD/FreeBSD-compatible)
clear
echo -n "Enter MySQL root password: "
stty -echo  # Disable input echo
read DB_PASS
stty echo   # Re-enable input echo
echo  # Move to a new line

# Hand the password to the MySQL client via the environment.
# This avoids the "Enter password:" prompt and keeps the password
# out of the process list (more secure than -p on the command line).
export MYSQL_PWD="$DB_PASS"

# Function to list databases
list_databases() {
    echo "------------------------"
    echo "      DATABASES"
    echo "------------------------"
    mysql -u root -e "SHOW DATABASES;" | tail -n +2 | awk '{printf " - %s\n", $1}'
    echo "------------------------"
}

# Function to add a database
add_database() {
    while true; do
        echo -n "Enter new database name (CTRL+C to quit): "
        read DB_NAME
        DB_NAME=$(echo "$DB_NAME" | tr -d ' ')  # Remove spaces

        if [ -z "$DB_NAME" ]; then
            echo "Error: Database name cannot be empty. Try again."
            continue
        fi

        # Check if database already exists
        DB_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';")
        if [ "$DB_EXISTS" -gt 0 ]; then
            echo "Error: Database '$DB_NAME' already exists. Choose another name."
            continue
        fi

        break
    done

    CREATE_OUTPUT=$(mysql -u root -e "CREATE DATABASE \`$DB_NAME\`;" 2>&1)
    if [ $? -eq 0 ]; then
        echo ""
        echo "+----------------------------------------+"
        echo "|  SUCCESS                                |"
        echo "+----------------------------------------+"
        echo "  Database '$DB_NAME' was created."
        echo "+----------------------------------------+"
    else
        echo ""
        echo "+----------------------------------------+"
        echo "|  ERROR: DATABASE WAS NOT CREATED        |"
        echo "+----------------------------------------+"
        echo "  Name   : $DB_NAME"
        echo "  Reason :"
        printf '%s\n' "$CREATE_OUTPUT" | sed 's/^/    /'
        echo "+----------------------------------------+"
    fi
}

# Function to remove a database
remove_database() {
    echo -n "Enter database name to remove (CTRL+C to quit): "
    read DB_NAME

    # Check if database exists
    DB_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';")

    if [ "$DB_EXISTS" -eq 0 ]; then
        echo "Error: Database '$DB_NAME' does not exist. Returning to main menu."
        return
    fi

    mysql -u root -e "DROP DATABASE \`$DB_NAME\`;"
    echo "Database '$DB_NAME' removed successfully."
}

# Function to list all users with their hosts
list_users() {
    echo "------------------------"
    echo "        USERS"
    echo "------------------------"
    mysql -u root -e "SELECT user, host FROM mysql.user;" | tail -n +2 | awk '{printf " - %s@%s\n", $1, $2}'
    echo "------------------------"
}

# Function to add a user
add_user() {
    while true; do
        echo -n "Enter new username (CTRL+C to quit): "
        read USERNAME
        USERNAME=$(echo "$USERNAME" | tr -d ' ')  # Remove spaces

        if [ -z "$USERNAME" ]; then
            echo "Error: Username cannot be empty. Try again."
            continue
        fi

        # Check if user already exists
        USER_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='$USERNAME';")
        if [ "$USER_EXISTS" -gt 0 ]; then
            echo "Error: User '$USERNAME' already exists. Choose another username."
            continue
        fi

        break
    done

    echo -n "Enter password for new user: "
    stty -echo  # Disable input echo
    read PASSWORD
    stty echo   # Re-enable input echo
    echo  # Move to a new line

    mysql -u root -e "CREATE USER '$USERNAME'@'localhost' IDENTIFIED BY '$PASSWORD';"
    echo "User '$USERNAME' created successfully."

    # Ask if the user should be assigned to a database
    while true; do
        echo -n "Should this user be assigned to a database? (y/n): "
        read ASSIGN_DB
        case "$ASSIGN_DB" in
            y|Y)
                echo -n "Enter the database name to assign: "
                read DB_NAME
                # Check if database exists
                DB_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';")
                if [ "$DB_EXISTS" -eq 0 ]; then
                    echo "Error: Database '$DB_NAME' does not exist. Returning to main menu."
                else
                    mysql -u root -e "GRANT ALL PRIVILEGES ON `$DB_NAME`.* TO '$USERNAME'@'localhost';"
                    mysql -u root -e "FLUSH PRIVILEGES;"
                    echo "User '$USERNAME' now has access to database '$DB_NAME'."
                fi
                break
                ;;
            n|N)
                echo "User '$USERNAME' was created without database access."
                break
                ;;
            *)
                echo "Invalid input. Please enter 'y' for yes or 'n' for no."
                ;;
        esac
    done
}

# Function to remove a user (handling all host entries)
remove_user() {
    echo -n "Enter username to remove (CTRL+C to quit): "
    read USERNAME

    # Check if user exists
    USER_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='$USERNAME';")

    if [ "$USER_EXISTS" -eq 0 ]; then
        echo "Error: User '$USERNAME' does not exist. Returning to main menu."
        return
    fi

    echo "Removing user '$USERNAME' from all hosts..."
    mysql -u root -e "SELECT CONCAT('DROP USER ', QUOTE(user), '@', QUOTE(host), ';') FROM mysql.user WHERE user='$USERNAME';" \
        | tail -n +2 | mysql -u root 2>/dev/null

    mysql -u root -e "FLUSH PRIVILEGES;"

    echo "User '$USERNAME' has been removed successfully."
}

# Function to change a user's password
change_user_password() {
    echo -n "Enter username whose password you want to change (CTRL+C to quit): "
    read USERNAME

    # Check if user exists
    USER_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='$USERNAME';")

    if [ "$USER_EXISTS" -eq 0 ]; then
        echo "Error: User '$USERNAME' does not exist. Returning to main menu."
        return
    fi

    echo -n "Enter new password for user '$USERNAME': "
    stty -echo
    read PASSWORD
    stty echo
    echo  # Move to a new line

    mysql -u root -e "ALTER USER '$USERNAME'@'localhost' IDENTIFIED BY '$PASSWORD';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    echo "Password for user '$USERNAME' has been updated successfully."
}

# Function to assign an existing user to an existing database
assign_user_to_db() {
    echo -n "Enter username to assign (CTRL+C to quit): "
    read USERNAME

    # Check if user exists; if not, return to main menu
    USER_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM mysql.user WHERE user='$USERNAME';")
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo "Error: User '$USERNAME' does not exist. Returning to main menu."
        return
    fi

    echo -n "Enter the database name to assign: "
    read DB_NAME

    # Check if database exists; if not, return to main menu
    DB_EXISTS=$(mysql -u root -sN -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DB_NAME';")
    if [ "$DB_EXISTS" -eq 0 ]; then
        echo "Error: Database '$DB_NAME' does not exist. Returning to main menu."
        return
    fi

    mysql -u root -e "GRANT ALL PRIVILEGES ON `$DB_NAME`.* TO '$USERNAME'@'localhost';"
    mysql -u root -e "FLUSH PRIVILEGES;"
    echo "User '$USERNAME' now has access to database '$DB_NAME'."
}

# Main menu
while true; do
    echo ""
    echo "=================================================="
    echo "  MariAdmin - MariaDB/MySQL Management Menu"
    echo "        v0.1 - Ozgur Konstantin Kazancci"
    echo "=================================================="
    echo "1) List databases"
    echo "2) Add a database"
    echo "3) Remove a database"
    echo "4) List users"
    echo "5) Add a user"
    echo "6) Remove a user"
    echo "7) Assign a user to a DB"
    echo "8) Change user password"
    echo "9) Exit"
    echo -n "Choose an option: "
    read OPTION

    case $OPTION in
        1) list_databases ;;
        2) add_database ;;
        3) remove_database ;;
        4) list_users ;;
        5) add_user ;;
        6) remove_user ;;
        7) assign_user_to_db ;;
        8) change_user_password ;;
        9) exit 0 ;;
        *) echo "Invalid option. Try again." ;;
    esac
done
