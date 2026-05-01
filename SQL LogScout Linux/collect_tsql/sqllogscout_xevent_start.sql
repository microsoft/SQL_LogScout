ALTER EVENT SESSION [sqllogscout_XEvent] ON SERVER 
ADD TARGET package0.event_file(SET filename=N'/var/opt/mssql/log/sqlcontainer80a_container_instance_sqllogscout_xevent.xel',max_file_size=(500),max_rollover_files=(50))
GO
ALTER EVENT SESSION [sqllogscout_XEvent] on server state = start
GO

