# 🛠️ MariAdmin

MariAdmin is a single POSIX shell script that gives you a friendly text menu for the database chores you'd otherwise type out by hand: creating and dropping databases, adding and removing users, handing out privileges, and rotating passwords. Version **0.4** uses the installed `mariadb` client, falling back to `mysql`, and is designed for **OpenBSD**, **FreeBSD** and **Linux**.

---

## ✨ Features

- **List databases** — a tidy view of the server's databases, with query failures reported.
- **Add a database** — with empty-name and duplicate checks, identifier quoting, and an honest success/failure report.
- **Remove a database** — existence-checked, with the name retyped to confirm removal.
- **List users** — shown as `user@host`, with query failures reported.
- **Add a user** — created at `localhost`, with an optional prompt to grant it access to a database on the spot.
- **Remove a user** — lists the existing accounts first, explains that only the username is entered (e.g. `webuser` for `webuser@localhost`), removes all host entries after confirmation and blocks removal of the connected administrative username.
- **Assign a user to a database** — verifies the user and database exist and grants access to the named database, including literal underscores.
- **Change a user's password** — hidden-input password rotation for `localhost` accounts, with refreshed credentials when changing the active account's password.
- **Safe by default** — hidden password entry, preserved whitespace, terminal restoration on exit and handled signals, and explicit error messages.
- **Choose the connection** — select the administrative account and local server instance, then see the target, authenticated identity and database software (MariaDB, MySQL or Percona Server, with version) on every screen.

---

## 📋 Requirements

- A POSIX-compatible `/bin/sh`.
- The `mariadb` or `mysql` command-line client on your `PATH`.
- Standard shell utilities, including `mktemp`, `sed`, and `stty`.
- A running local MariaDB or MySQL server and an administrative account with the privileges needed for the selected operations.

---

## 📖 Usage

From the downloaded repository, run:

```sh
sh mariadmin.sh
```

The default connection uses database account `root` over the local Unix socket. MariAdmin first tries the available authentication settings and prompts for a password if needed. Password typing is hidden on a terminal.

To select another administrative account or socket:

```sh
sh mariadmin.sh --user dbadmin
sh mariadmin.sh --user dbadmin --socket /var/run/mysql/mysql.sock
```

To select a local instance over TCP:

```sh
sh mariadmin.sh --host 127.0.0.1 --port 3306 --user dbadmin
```

Use `--user NAME` to choose the administrative account (default: `root`), `--socket PATH` to select a Unix socket, or `--host HOST` and `--port PORT` to use local TCP. Supported hosts are `localhost`, `127.0.0.1`, and `::1`; other hosts are rejected. Do not combine `--socket` with `--host` or `--port`. Run `sh mariadmin.sh --help` for usage or `sh mariadmin.sh --version` for the version.

The menu identifies the connection target, authenticated account and database software, followed by these actions:

```text
==================================================
  MariAdmin - MariaDB/MySQL Management Menu
        v0.4 - Ozgur Konstantin Kazancci
==================================================
Connection: localhost via socket /var/run/mysql/mysql.sock
Server: dbhost:3306 | Account: root@localhost
Software: MariaDB 11.4.12
==================================================
  1) List databases
  2) Add a database
  3) Remove a database
  4) List users
  5) Add a user
  6) Remove a user
  7) Assign a user to a DB
  8) Change user password
  9) Exit
--------------------------------------------------
Choose an option:
```

Pick a number and follow the prompts. At an action's input prompt, press **Enter** to cancel that action or **Ctrl+C** to exit. Database and user removal require retyping the name. A blank initial authentication password exits the script; blank new passwords are not accepted.

---

## 🔐 Security notes

- SQL is sent through the client's standard input. Neither administrative passwords nor passwords in account-management SQL are placed in client command-line arguments.
- Supplied administrative passwords are stored in a temporary client option file, with mode `600` inside a private directory with mode `700`. MariAdmin removes these files on normal exit and handled signals. It does not export `MYSQL_PWD` to client processes.
- Once a password is supplied, MariAdmin uses its private option file instead of client defaults or login-path settings, so a stale saved password cannot override the supplied password. For a nonstandard local socket, select it explicitly with `--socket`.
- Password-related query failures display an error code instead of echoing SQL or server messages that could contain the password.
- Password input preserves spaces, quotes, and backslashes. Each SQL connection removes `NO_BACKSLASH_ESCAPES` from its own session's SQL mode so string escaping is consistent; global server settings are unchanged.
- Connections are restricted to local sockets and the supported local host values. Verify the displayed local instance before performing administrative operations.

---

## 📝 Notes & limitations

- Database names and usernames entered in menu actions accept letters, digits, and underscores. Existing accounts with other username characters need to be managed using another client.
- Usernames are entered without the host part: type `webuser`, not `webuser@localhost`. Input containing `@` is rejected with an example and no SQL is sent.
- Creating users, granting privileges, and changing passwords target **`'username'@'localhost'`**.
- Removing a user targets **all host entries for that username**. To remove the connected administrative username, connect using another administrator first.
- New grants escape database-name wildcards as required by the server's privilege mode. Existing grants are not rewritten by upgrading the script.
- Passwords are read as a single line. Empty passwords are not supported by the interactive prompts.
- Server authentication plugins and the administrator's privileges still determine which operations are available.
- Terminal restoration and temporary-file cleanup cannot run after an uncatchable process termination such as `SIGKILL`.

---

## 🤝 Contributing

Issues and pull requests are welcome. Keep changes compatible with POSIX `sh`, and run:

```sh
sh -n mariadmin.sh
sh tests/test-mariadmin.sh
```

---

## 📄 License & ChangeLog

**License**: Do with it what you will; just don't blame me for dropped tables. :/

**ChangeLog**:

**11/11/2026**:

- Updated mariadmin.sh to v0.4; the `--help` text now reads the version from the script instead of a hard-coded string.

- Remove a user now lists the existing accounts before the prompt and explains, with an example, that only the username is entered (type `webuser` to remove `webuser@localhost`).

- All username prompts (add, remove, assign and change password) now reject `user@host` input with an explanatory example instead of a generic "Invalid username" message, and send no SQL.

- Improved the connection banner: the Connection and Server lines are now bold green instead of dim gray, a new Software line shows the database software (MariaDB, MySQL or Percona Server) and its version, and a separator line closes the banner.

- Added regression checks for the user list, the username-only hint, `user@host` rejection and software detection (70 checks in total).

- Verified v0.4 on FreeBSD 15.1 with MariaDB 10.6.27.

**09/09/2026**:

- Updated mariadmin.sh to v0.3, fixing literal-underscore database grants, SQL-mode-dependent password escaping, and password exposure in client arguments and query errors.

- Added explicit local connection and administrative-account options, visible connection identity, and `mariadb`/`mysql` client detection.

- Updated authentication so supplied passwords take precedence over stale client passwords and active-account password changes refresh and verify the connection.

- Corrected query-status checks and all-host user removal, including escaped host names, failure reporting, confirmation, and prevention of connected-account removal.

- Preserved leading and trailing whitespace in input and restored terminal settings on exit and handled signals.

- Added regression checks and updated usage documentation.

- Verified v0.3 on Ubuntu 26.04 LTS with MariaDB 11.8.6 and added Linux to the supported platforms.

- Verified v0.3 on OpenBSD 7.9 with MariaDB 11.4.12 and made the regression tests compatible with the native shell and interactive console.

**15/07/2026**:

- Rewrote mariadmin.sh (v0.2), fixing the critical bug where unescaped backticks in the GRANT statements caused shell command substitution — so assigning a user to a database now actually grants privileges instead of silently failing (and the command-execution hole is closed).

- Hardened all input handling: identifiers are validated against ^[A-Za-z0-9_]+$ (blocking SQL injection), passwords are safely escaped, and every mysql call's exit status is checked before printing success.

- Added dual-mode authentication: the script probes for passwordless root access (unix_socket / defaults file) and only prompts for a password when needed, always operating on localhost.

- New UX: colored menus (auto-disabled when not a TTY), "ENTER to return to menu" on every prompt (no CTRL+C), and the screen clears each step so the menu stays on top with interaction below.

- Verified end-to-end on OpenBSD 7.9 and FreeBSD 15.1 — GRANT fix, quoted-password login, and injection rejection all confirmed, with before/after snapshots identical (zero damage to existing databases).

---

> **Disclaimer:** MariAdmin will faithfully do exactly what you tell it — including the regrettable bits. Always keep backups. The author is not responsible for databases dropped in haste.
