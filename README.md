**aws-log-shipping-from-onprem-ec2-to-rds-sql-server**

The Scripts in this repository is t configure logshipping as part of migration or disater recovery from an on-premises sql server or SQL Server on EC2 to RDS for SQL Server with the assumption that you have the following pre-requisites completed .



*1. On-premises or Amazon EC2 SQL Server instance*

*2. Amazon RDS for SQL Server instance*

*2. An Amazon Simple Storage Service (Amazon S3) bucket*

*4. SQL credentials to connect to Amazon RDS stored in AWS Secrets Manager*

*5. An AWS Identity and Access Management (IAM) role to access the S3 bucket and secret*

*6. AWS Storage Gateway for file storage*


The repository contains the following files 
   
   
   1)ConfigFile.txt
   
   2)Logshipping_Full_Backup.ps1
  
  3)Logshipping_Restore.ps1
	
  4)Full_Backup_Job.sql
	
  5)Restore_Job.sql
  
Config file.txt - this is the input file whee you would provide the source , destination sql servers , databases and other details.

These scripts needs to be saved in the source Database server and execute it in the source sql intance . The jobs will be created in the source instance.

The PowerShell script “Logshipping_Full_Backup.ps1”” takes the full backup of the user provided databases in the config file and “Logshipping_Restore.ps1 will restore the full backup and all the log backups that was taken in the source server and copied to an S3 bucket .These scripts can be scheduled via SQL server jobs using the job creation scripts (.sql).User needs to provide the source , destination and other details in the config file and the scripts will run in its schedule and the log backups from source database gets continuously applied to the destination database .

Please refer this blog post for more details on this ,

https://aws.amazon.com/blogs/database/use-native-sql-server-log-shipping-and-powershell-scripts-to-synchronize-data-to-amazon-rds-for-sql-server/



## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

