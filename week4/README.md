# Week 4 - Server Cloning, Backups and Database Replication

In this assignment, I created a second Linux server using
a snapshot of my existing server in CSC cPouta.

The goal was to configure automatic website backups and
continuous MariaDB replication between two servers.

## Servers

Server A is the original server. It runs the Week 2 Flask
application and updates the visitor counter.

Server B is the replica. It receives database changes
automatically and displays the counter without increasing it.

- Server A: http://195.148.23.48/viikko2/
- Server B: http://195.148.20.234/viikko4/

## Automatic Backups

I created a Bash script that uses rsync over SSH to copy
website files from Server A to Server B.

Source:
- /var/www/html/

Backup destination:
- /srv/backups/week4/

Backups run automatically every hour using Cron.

Cron configuration:

    0 * * * * /home/ubuntu/viikko4/backup.sh >> /home/ubuntu/viikko4/cron.log 2>&1

Each backup is stored in a separate timestamped directory.
The script records successful and failed backups in a log.

A dedicated Linux user called backuprecv handles the
backup transfers. SSH key authentication and restricted
file permissions are used.

## MariaDB Replication

Server A is the primary database server.

- Server ID: 1
- Binary logging enabled
- Binary log format: ROW

Server B is the replica.

- Server ID: 2
- Read-only mode enabled
- Only the viikko2 database is replicated

A dedicated replication user connects from Server B
to Server A.

The Flask application on Server B uses a separate
database user with SELECT permission only.

The visitor counter is read from the local replica.
Refreshing the Week 4 website does not increase it.

## Testing

I verified that:

- Both servers are accessible.
- Database changes are replicated from A to B.
- Refreshing the Week 4 page does not increase the counter.
- Two automatic hourly backups completed successfully.
- A test HTML file was restored successfully.
- The restored file matched the backup.
- Server B was rebooted successfully.
- Nginx, MariaDB, Flask and Cron started after reboot.
- Database replication continued working after reboot.

## Files

- app.py - Read-only Flask application
- templates/index.html - Week 4 website
- backup.sh - Automatic backup script
- requirements.txt - Python dependencies
- config/ - MariaDB configuration examples

Passwords, private SSH keys, database dumps and backup
archives are not included in this repository.

## What I Learned

I learned how to clone a Linux server, configure automatic
backups and set up MariaDB replication.

I also learned more about Linux file permissions,
SSH security and testing server recovery.
