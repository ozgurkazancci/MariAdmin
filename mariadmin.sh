# 🛠️ MariAdmin

MariAdmin is a single, dependency-free shell script that gives you a friendly text menu for the database chores you'd otherwise type out by hand: creating and dropping databases, adding and removing users, handing out privileges, and rotating passwords. It speaks the `mysql`/`mariadb` client and runs happily on **OpenBSD** and **FreeBSD** — tested on both — and never asks for more than your root password (once, with the echo turned off).

---

## ✨ Features

- **List databases** — a tidy, de-cluttered view of everything on the server.
- **Add a database** — with empty-name and duplicate checks, identifier quoting (so names like `en.mysite_org` work), and an honest success/failure report instead of a misleading "success".
- **Remove a database** — existence-checked before it touches anything.
- **List users** — shown as `user@host`.
- **Add a user** — created at `localhost`, with an optional prompt to grant it access to a database on the spot.
- **Remove a user** — cleans up *all* host entries for that username, not just one.
- **Assign a user to a database** — verifies both the user and the database exist before granting; returns to the main menu otherwise.
- **Change a user's password** — quick, hidden-input password rotation.
- **Safe by default** — hidden password entry, `(CTRL+C to quit)` hints on every input prompt, and clear boxed error messages.

---

## 📋 Requirements

- A POSIX-compatible `/bin/sh` (the OpenBSD and FreeBSD default `sh` is fine).
- The `mysql` / `mariadb` command-line client installed and on your `PATH`.
- A running **MariaDB** (or MySQL) server.
- The **root** database password (or another account with sufficient privileges).

---

## 📖 Usage

Run the script and enter your MariaDB root password when asked (your typing stays hidden):

```text
Enter MySQL root password:
================================================
  MariAdmin - MariaDB/MySQL Management Menu
        v0.1 - Ozgur Konstantin Kazancci
================================================
1) List databases
2) Add a database
3) Remove a database
4) List users
5) Add a user
6) Remove a user
7) Assign a user to a DB
8) Change user password
9) Exit
Choose an option:
```

Pick a number and follow the prompts. At any input prompt you can press **Ctrl+C** to quit back to your shell.

### Example: a clear failure

Because MariAdmin actually checks whether the command worked, a bad database name gets an honest answer instead of a false "success":

```text
+----------------------------------------+
|  ERROR: DATABASE WAS NOT CREATED        |
+----------------------------------------+
  Name   : some bad name
  Reason :
    ERROR 1064 (42000) at line 1: You have an error in your SQL syntax...
+----------------------------------------+
```

---

## 🔐 Security notes

- The root password is read **once**, with terminal echo disabled, and passed to the client through the `MYSQL_PWD` environment variable. It is **never** placed on the command line, so it won't show up in `ps` output and won't trigger MariaDB's *"Using a password on the command line interface can be insecure"* warning.
- New users and grants are scoped to **`localhost`** by design. If you need users reachable from other hosts, adjust the `CREATE USER` / `GRANT` host part to suit.
- This is an administrative convenience tool. Run it as a trusted operator on a trusted machine — it can drop databases and delete users.

---

## 📝 Notes & limitations

- Identifiers are backtick-quoted, so database names containing dots (e.g. `en.mysite_org`) are accepted. MariaDB encodes such characters on disk, so the on-disk data directory name may not read literally.
- User existence is matched by **username** (any host). This is intentional given the localhost-only design above.
- The script targets the standard `mysql`/`mariadb` client behaviour; exotic auth plugins may need tweaks.

---

## 🤝 Contributing

Issues and pull requests are welcome. Keep it POSIX `sh`-clean (test with `sh -n mariadmin.sh`) so it stays portable across OpenBSD and FreeBSD.

---

## 📄 License

Do with it what you will; just don't blame me for dropped tables. :/

---

> **Disclaimer:** MariAdmin will faithfully do exactly what you tell it — including the regrettable bits. Always keep backups. The author is not responsible for databases dropped in haste.
