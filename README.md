aws-log-shipping-from-onprem-ec2-to-rds-sql-server

The Scripts in this repository is part of the blog that uses a custom logshipping to synchronize the data from on-premises or EC2 SQL Server to RDS for SQL Server.
It contains the following files 
•	ConfigFile.txt
•	Logshipping_Full_Backup.ps1
•	Logshipping_Restore.ps1
•	Full_Backup_Job.sql
•	Restore_Job.sql


The PowerShell script “Logshipping_Full_Backup.ps1”” takes the full backup of the user provided databases in the config file and “Logshipping_Restore.ps1 will restore the full backup and all the log backups that was taken in the source server and copied to an S3 bucket .These scripts can be scheduled via SQL server jobs using the job creation scripts (.sql).User needs to provide the source , destination and other details in the config file and the scripts will run in its schedule and the log backups from source database gets continuously applied to the destination database .

Please refer to the blog for more details.


## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

