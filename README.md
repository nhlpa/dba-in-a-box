<a name="header1"></a>
# DBA In A Box
[![licence badge]][licence]
[![stars badge]][stars]
[![forks badge]][forks]
[![issues badge]][issues]

Useful scripts and jobs to make life as a part-time DBA easier.

## Scripts Included
- [sp_whoIsActive][1] by Adam Machanic
- [DatabaseIntegrityCheck][2] by Ola Hallengren
- [IndexOptimize][7] by Ola Hallengren
- [sp_Blitz][3] by Brent Ozar
- [sp_BlitzCache][4] by Brent Ozar
- [sp_BlitzIndex][5] by Brent Ozar
- [sp_EasyButton][6] by Pim Brouwers

## Getting Started

> To install in a database other than `master`, simply change Line 1 of `install.sql`

Download and run `install.sql`, then sit back and relax.

This will install the scripts list above in the `master` database. The following SQL Agent Jobs will also be installed:

1. `DBA_CHECKDB`: Run `CHECKDB` on all databases - weekly (Sunday).
2. `DBA_CYCLELOGS`: Cycle log and error log files - daily (midnight).
3. `DBA_REBUILDINDEXES`: Rebuild indexes on all user databases - weekly (Saturday).
4. `DBA_STATISTICS`: Update statistics on all user databases - daily (midnight).
5. `DBA_WAITSTATS`: Capture a snapshot of server wait statistics - daily (midnight).
6. `DBA_WHOISACTIVE`: Capture a snapshot of `sp_whoIsActive` - 60s
7. `DBA_PURGEHISTORY`: Purge `msdb` backup & job history of data older than 60 days - daily (midnight).

> All jobs are created in the *disabled* state and must be *enabled*.

## License

[dba-in-a-box uses the GNU GENERAL PUBLIC LICENSE.](LICENSE.md)

[*Back to top*](#header1)

[licence badge]:https://img.shields.io/badge/license-GNU-blue.svg
[stars badge]:https://img.shields.io/github/stars/pimbrouwers/dba-in-a-box.svg
[forks badge]:https://img.shields.io/github/forks/pimbrouwers/dba-in-a-box.svg
[issues badge]:https://img.shields.io/github/issues/pimbrouwers/dba-in-a-box.svg

[licence]:https://github.com/pimbrouwers/dba-in-a-box/blob/master/LICENSE.md
[stars]:https://github.com/pimbrouwers/dba-in-a-box/stargazers
[forks]:https://github.com/pimbrouwers/dba-in-a-box/network
[issues]:https://github.com/pimbrouwers/dba-in-a-box/issues

[1]: http://whoisactive.com/downloads/
[2]: https://github.com/olahallengren/sql-server-maintenance-solution/blob/master/DatabaseIntegrityCheck.sql
[3]: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/blob/dev/sp_Blitz.sql
[4]: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/blob/dev/sp_BlitzCache.sql
[5]: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/blob/dev/sp_BlitzIndex.sql
[6]: https://github.com/pimbrouwers/sp_EasyButton/blob/master/sp_EasyButton.sql
[7]: https://github.com/olahallengren/sql-server-maintenance-solution/blob/master/IndexOptimize.sql
