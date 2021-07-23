/++
Connect to a MySQL/MariaDB server (unsafe version).

This is the unsafe API for the Connection type. It publicly imports
`mysql.impl.connection`, and also provides the unsafe version of the API for
preparing statements. Note that unsafe prepared statements actually use safe
code underneath.

Note that the common pieces of the connection are documented and currently
reside in `mysql.impl.connection`. Please see this module for documentation of
the connection object.

This module also contains the soon-to-be-deprecated BackwardCompatPrepared type.

$(SAFE_MIGRATION)
+/
module mysql.unsafe.connection;

public import mysql.impl.connection;
import mysql.unsafe.prepared;
import mysql.unsafe.commands;
private import CS = mysql.safe.connection;

/++
Convenience functions.

Returns: an UnsafePrepared instance based on the result of the corresponding `mysql.safe.connection` function.

See that module for more details on how these functions work.
+/
UnsafePrepared prepare(Connection conn, const(char[]) sql) @safe
{
	return CS.prepare(conn, sql).unsafe;
}

/// ditto
UnsafePrepared prepareFunction(Connection conn, string name, int numArgs) @safe
{
	return CS.prepareFunction(conn, name, numArgs).unsafe;
}

/// ditto
UnsafePrepared prepareProcedure(Connection conn, string name, int numArgs) @safe
{
	return CS.prepareProcedure(conn, name, numArgs).unsafe;
}
