module mysql.commands;
version(MySQLSafeMode)
	public import mysql.safe.commands;
else
	public import mysql.unsafe.commands;
