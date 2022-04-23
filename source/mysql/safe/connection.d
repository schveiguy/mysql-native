/++
Connect to a MySQL/MariaDB server (safe version).

This is the @safe API for the Connection type. It publicly imports `mysql.impl.connection`, and also provides the safe version of the API for preparing statements.

Note that the common pieces of the connection are documented and currently
reside in `mysql.impl.connection`. Please see this module for documentation of
the connection object.

$(SAFE_MIGRATION)
+/
module mysql.safe.connection;

public import mysql.impl.connection;
import mysql.safe.prepared;
import mysql.safe.commands;


@safe:

/++
Submit an SQL command to the server to be compiled into a prepared statement.

This will automatically register the prepared statement on the provided connection.
The resulting `mysql.impl.prepared.SafePrepared` can then be used freely on ANY
`mysql.impl.connection.Connection`, as it will automatically be registered upon
its first use on other connections. Or, pass it to
`mysql.impl.connection.Connection.register` if you prefer eager registration.

Internally, the result of a successful outcome will be a statement handle - an ID -
for the prepared statement, a count of the parameters required for
execution of the statement, and a count of the columns that will be present
in any result set that the command generates.

The server will then proceed to send prepared statement headers,
including parameter descriptions, and result set field descriptions,
followed by an EOF packet.

Throws: `mysql.exceptions.MYX` if the server has a problem.

Params:
	conn = The connection to use.
	sql = The SQL statement to prepare.
+/
SafePrepared prepare(Connection conn, const(char[]) sql)
{
	auto info = conn.registerIfNeeded(sql);
	return SafePrepared(sql, info.headers, info.numParams);
}

/++
Convenience function to create a prepared statement which calls a stored function.

Be careful that your `numArgs` is correct. If it isn't, you may get a
`mysql.exceptions.MYX` with a very unclear error message.

Throws: `mysql.exceptions.MYX` if the server has a problem.

Params:
	conn = The connection to use.
	name = The name of the stored function.
	numArgs = The number of arguments the stored procedure takes.
+/
SafePrepared prepareFunction(Connection conn, string name, int numArgs)
{
	auto sql = "select " ~ name ~ preparedPlaceholderArgs(numArgs);
	return prepare(conn, sql);
}

/++
Convenience function to create a prepared statement which calls a stored procedure.

OUT parameters are currently not supported. It should generally be
possible with MySQL to present them as a result set.

Be careful that your `numArgs` is correct. If it isn't, you may get a
`mysql.exceptions.MYX` with a very unclear error message.

Throws: `mysql.exceptions.MYX` if the server has a problem.

Params:
	conn = The connection to use.
	name = The name of the stored procedure.
	numArgs = The number of arguments the stored procedure takes.

+/
SafePrepared prepareProcedure(Connection conn, string name, int numArgs)
{
	auto sql = "call " ~ name ~ preparedPlaceholderArgs(numArgs);
	return prepare(conn, sql);
}

