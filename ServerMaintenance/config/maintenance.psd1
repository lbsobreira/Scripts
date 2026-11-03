@{
    # Servers the weekly maintenance runs on. Names in exclude-servers.txt are skipped.
    Servers          = @('LAB-FS01', 'LAB-WEB01', 'LAB-WEB02', 'LAB-APP01', 'LAB-SQL01')

    # Files older than this are removed from the folders below.
    LogRetentionDays = 14
    TempRetentionDays = 7
    LogFolders       = @(
        'C:\inetpub\logs\LogFiles'
        'C:\Windows\Logs\CBS'
        'D:\AppLogs'
    )

    # Restarted after the cleanup when they are running.
    RestartServices  = @('W3SVC', 'Spooler')

    # Local log and transcript folder on the machine running the script.
    LogFolder        = 'C:\Scripts\ServerMaintenance\Logs'

    Mail             = @{
        SmtpServer = 'smtp.lab.local'
        From       = 'maintenance@lab.local'
        To         = @('ops@lab.local')
        Port       = 25
    }
}
