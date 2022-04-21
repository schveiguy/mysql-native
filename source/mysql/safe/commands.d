/++
Use a DB via plain SQL statements (safe version).

Commands that are expected to return a result set - queries - have distinctive
methods that are enforced. That is it will be an error to call such a method
with an SQL command that does not produce a result set. So for commands like
SELECT, use the `query` functions. For other commands, like
INSERT/UPDATE/CREATE/etc, use `exec`.

This is the @safe version of mysql's command module, and as such uses the @safe
rows and result ranges, and the `MySQLVal` type. For the `Variant` unsafe
version, please import `mysql.unsafe.commands`.

$(SAFE_MIGRATION)
+/

module mysql.safe.commands;

import std.conv;
import std.exception;
import std.range;
import std.typecons;
import std.variant;

import mysql.safe.connection;
import mysql.exceptions;
import mysql.safe.prepared;
import mysql.protocol.comms;
import mysql.protocol.constants;
import mysql.protocol.extra_types;
import mysql.protocol.packets;
import mysql.impl.result;
import mysql.types;

/// This feature is not yet implemented. It currently has no effect.
/+
A struct to represent specializations of returned statement columns.

If you are executing a query that will include result columns that are large objects,
it may be expedient to deal with the data as it is received rather than first buffering
it to some sort of byte array. These two variables allow for this. If both are provided
then the corresponding column will be fed to the stipulated delegate in chunks of
`chunkSize`, with the possible exception of the last chunk, which may be smaller.
The bool argument `finished` will be set to true when the last chunk is set.

Be aware when specifying types for column specializations that for some reason the
field descriptions returned for a resultset have all of the types TINYTEXT, MEDIUMTEXT,
TEXT, LONGTEXT, TINYBLOB, MEDIUMBLOB, BLOB, and LONGBLOB lumped as type 0xfc
contrary to what it says in the protocol documentation.
+/
struct ColumnSpecialization
{
	size_t  cIndex;    // parameter number 0 - number of params-1
	ushort  type;
	uint    chunkSize; /// In bytes
	void delegate(const(ubyte)[] chunk, bool finished) @safe chunkDelegate;
}
///ditto
alias CSN = ColumnSpecialization;

@safe:

/++
Execute an SQL command or prepared statement, such as INSERT/UPDATE/CREATE/etc.

This method is intended for commands such as which do not produce a result set
(otherwise, use one of the `query` functions instead.) If the SQL command does
produces a result set (such as SELECT), `mysql.exceptions.MYXResultRecieved`
will be thrown.

If `args` is supplied, the sql string will automatically be used as a prepared
statement. Prepared statements are automatically cached by mysql-native,
so there's no performance penalty for using this multiple times for the
same statement instead of manually preparing a statement.

If `args` and `prepared` are both provided, `args` will be used,
and any arguments that are already set in the prepared statement
will automatically be replaced with `args` (note, just like calling
`mysql.impl.prepared.SafePrepared.setArgs`, this will also remove all
`mysql.impl.prepared.SafeParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.impl.prepared.SafeParameterSpecialization`, use
`mysql.safe.connection.prepare` to manually create a
`mysql.impl.prepared.SafePrepared`, and set your parameter specializations using
`mysql.impl.prepared.SafePrepared.setArg` or
`mysql.impl.prepared.SafePrepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.impl.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
args = The arguments to be passed in the `mysql.impl.prepared.SafePrepared`.

Returns: The number of rows affected.

Example:
---
auto myInt = 7;
auto rowsAffected = myConnection.exec("INSERT INTO `myTable` (`a`) VALUES (?)", myInt);
---
+/
ulong exec(Connection conn, const(char[]) sql)
{
	return execImpl(conn, ExecQueryImplInfo(false, sql));
}
///ditto
ulong exec(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return exec(conn, prepared);
}
///ditto
ulong exec(Connection conn, const(char[]) sql, MySQLVal[] args)
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return exec(conn, prepared);
}

///ditto
ulong exec(Connection conn, ref Prepared prepared)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	auto ra = execImpl(conn, prepared.getExecQueryImplInfo(preparedInfo.statementId));
	prepared._lastInsertID = conn.lastInsertID;
	return ra;
}
///ditto
ulong exec(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]))
{
	prepared.setArgs(args);
	return exec(conn, prepared);
}

///ditto
ulong exec(Connection conn, ref Prepared prepared, MySQLVal[] args)
{
	prepared.setArgs(args);
	return exec(conn, prepared);
}

/// Common implementation for `exec` overloads
package ulong execImpl(Connection conn, ExecQueryImplInfo info)
{
	ulong rowsAffected;
	bool receivedResultSet = execQueryImpl(conn, info, rowsAffected);
	if(receivedResultSet)
	{
		conn.purgeResult();
		throw new MYXResultRecieved();
	}

	return rowsAffected;
}

/++
Execute an SQL SELECT command or prepared statement.

This returns an input range of `mysql.impl.result.SafeRow`, so if you need random
access to the `mysql.impl.result.SafeRow` elements, simply call
$(LINK2 https://dlang.org/phobos/std_array.html#array, `std.array.array()`)
on the result.

If the SQL command does not produce a result set (such as INSERT/CREATE/etc),
then `mysql.exceptions.MYXNoResultRecieved` will be thrown. Use
`exec` instead for such commands.

If `args` is supplied, the sql string will automatically be used as a prepared
statement. Prepared statements are automatically cached by mysql-native,
so there's no performance penalty for using this multiple times for the
same statement instead of manually preparing a statement.

If `args` and `prepared` are both provided, `args` will be used,
and any arguments that are already set in the prepared statement
will automatically be replaced with `args` (note, just like calling
`mysql.impl.prepared.SafePrepared.setArgs`, this will also remove all
`mysql.impl.prepared.SafeParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.safe.prepared.ParameterSpecialization`, use
`mysql.safe.connection.prepare` to manually create a
`mysql.impl.prepared.SafePrepared`, and set your parameter specializations using
`mysql.impl.prepared.SafePrepared.setArg` or
`mysql.impl.prepared.SafePrepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.impl.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.
args = Arguments to the SQL statement or `mysql.safe.prepared.Prepared` struct.

Returns: A (possibly empty) `mysql.safe.result.ResultRange`.

Example:
---
ResultRange oneAtATime = myConnection.query("SELECT * from `myTable`");
Row[]       allAtOnce  = myConnection.query("SELECT * from `myTable`").array;

auto myInt = 7;
ResultRange rows = myConnection.query("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
---
+/
/+
Future text:
If there are long data items among the expected result columns you can use
the `csa` param to specify that they are to be subject to chunked transfer via a
delegate.

csa = An optional array of `ColumnSpecialization` structs. If you need to
use this with a prepared statement, please use `mysql.prepared.Prepared.columnSpecials`.
+/
SafeResultRange query(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null)
{
	return queryImpl(csa, conn, ExecQueryImplInfo(false, sql));
}
///ditto
SafeResultRange query(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return query(conn, prepared);
}

///ditto
SafeResultRange query(Connection conn, const(char[]) sql, MySQLVal[] args)
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return query(conn, prepared);
}

///ditto
SafeResultRange query(Connection conn, ref Prepared prepared)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	auto result = queryImpl(prepared.columnSpecials, conn, prepared.getExecQueryImplInfo(preparedInfo.statementId));
	prepared._lastInsertID = conn.lastInsertID; // Conceivably, this might be needed when multi-statements are enabled.
	return result;
}
///ditto
SafeResultRange query(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	prepared.setArgs(args);
	return query(conn, prepared);
}
///ditto
SafeResultRange query(Connection conn, ref Prepared prepared, MySQLVal[] args)
{
	prepared.setArgs(args);
	return query(conn, prepared);
}

/// Common implementation for `query` overloads
package SafeResultRange queryImpl(ColumnSpecialization[] csa,
	Connection conn, ExecQueryImplInfo info)
{
	ulong ra;
	enforce!MYXNoResultRecieved(execQueryImpl(conn, info, ra));

	conn._rsh = ResultSetHeaders(conn, conn._fieldCount);
	if(csa !is null)
		conn._rsh.addSpecializations(csa);

	conn._headersPending = false;
	return SafeResultRange(conn, conn._rsh, conn._rsh.fieldNames);
}

/++
Execute an SQL SELECT command or prepared statement where you only want the
first `mysql.impl.result.SafeRow`, if any.

If the SQL command does not produce a result set (such as INSERT/CREATE/etc),
then `mysql.exceptions.MYXNoResultRecieved` will be thrown. Use
`exec` instead for such commands.

If `args` is supplied, the sql string will automatically be used as a prepared
statement. Prepared statements are automatically cached by mysql-native,
so there's no performance penalty for using this multiple times for the
same statement instead of manually preparing a statement.

If `args` and `prepared` are both provided, `args` will be used,
and any arguments that are already set in the prepared statement
will automatically be replaced with `args` (note, just like calling
`mysql.impl.prepared.SafePrepared.setArgs`, this will also remove all
`mysql.impl.prepared.SafeParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.impl.prepared.SafeParameterSpecialization`, use
`mysql.safe.connection.prepare` to manually create a
`mysql.impl.prepared.SafePrepared`, and set your parameter specializations using
`mysql.impl.prepared.SafePrepared.setArg` or
`mysql.impl.prepared.SafePrepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.impl.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.
args = Arguments to SQL statement or `mysql.impl.prepared.SafePrepared` struct.

Returns: `Nullable!(mysql.impl.result.SafeRow)`: This will be null (check
		via `Nullable.isNull`) if the query resulted in an empty result set.

Example:
---
auto myInt = 7;
Nullable!Row row = myConnection.queryRow("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
---
+/
/+
Future text:
If there are long data items among the expected result columns you can use
the `csa` param to specify that they are to be subject to chunked transfer via a
delegate.

csa = An optional array of `ColumnSpecialization` structs. If you need to
use this with a prepared statement, please use `mysql.prepared.Prepared.columnSpecials`.
+/
/+
Future text:
If there are long data items among the expected result columns you can use
the `csa` param to specify that they are to be subject to chunked transfer via a
delegate.

csa = An optional array of `ColumnSpecialization` structs. If you need to
use this with a prepared statement, please use `mysql.prepared.Prepared.columnSpecials`.
+/
Nullable!SafeRow queryRow(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null)
{
	return queryRowImpl(csa, conn, ExecQueryImplInfo(false, sql));
}
///ditto
Nullable!SafeRow queryRow(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}
///ditto
Nullable!SafeRow queryRow(Connection conn, const(char[]) sql, MySQLVal[] args)
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}

///ditto
Nullable!SafeRow queryRow(Connection conn, ref Prepared prepared)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	auto result = queryRowImpl(prepared.columnSpecials, conn, prepared.getExecQueryImplInfo(preparedInfo.statementId));
	prepared._lastInsertID = conn.lastInsertID; // Conceivably, this might be needed when multi-statements are enabled.
	return result;
}
///ditto
Nullable!SafeRow queryRow(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}
///ditto
Nullable!SafeRow queryRow(Connection conn, ref Prepared prepared, MySQLVal[] args)
{
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}

/// Common implementation for `querySet` overloads.
package Nullable!SafeRow queryRowImpl(ColumnSpecialization[] csa, Connection conn,
	ExecQueryImplInfo info)
{
	auto results = queryImpl(csa, conn, info);
	if(results.empty)
		return Nullable!SafeRow();
	else
	{
		auto row = results.front;
		results.close();
		return Nullable!SafeRow(row);
	}
}

/++
Execute an SQL SELECT command or prepared statement where you only want the
first `mysql.result.Row`, and place result values into a set of D variables.

This method will throw if any column type is incompatible with the corresponding D variable.

Unlike the other query functions, queryRowTuple will throw
`mysql.exceptions.MYX` if the result set is empty
(and thus the reference variables passed in cannot be filled).

If the SQL command does not produce a result set (such as INSERT/CREATE/etc),
then `mysql.exceptions.MYXNoResultRecieved` will be thrown. Use
`exec` instead for such commands.

Only use the `const(char[]) sql` overload when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.impl.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
args = The variables, taken by reference, to receive the values.
+/
void queryRowTuple(T...)(Connection conn, const(char[]) sql, ref T args)
{
	return queryRowTupleImpl(conn, ExecQueryImplInfo(false, sql), args);
}

///ditto
void queryRowTuple(T...)(Connection conn, ref Prepared prepared, ref T args)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	queryRowTupleImpl(conn, prepared.getExecQueryImplInfo(preparedInfo.statementId), args);
	prepared._lastInsertID = conn.lastInsertID; // Conceivably, this might be needed when multi-statements are enabled.
}

/// Common implementation for `queryRowTuple` overloads.
package(mysql) void queryRowTupleImpl(T...)(Connection conn, ExecQueryImplInfo info, ref T args)
{
	ulong ra;
	enforce!MYXNoResultRecieved(execQueryImpl(conn, info, ra));

	auto rr = conn.getNextRow();
	/+if (!rr._valid)   // The result set was empty - not a crime.
		return;+/
	enforce!MYX(rr._values.length == args.length, "Result column count does not match the target tuple.");
	foreach (size_t i, dummy; args)
	{
		import taggedalgebraic.taggedalgebraic : get, hasType;
		enforce!MYX(rr._values[i].hasType!(T[i]),
			"Tuple "~to!string(i)~" type and column type are not compatible.");
		// use taggedalgebraic get to avoid extra calls.
		args[i] = get!(T[i])(rr._values[i]);
	}
	// If there were more rows, flush them away
	// Question: Should I check in purgeResult and throw if there were - it's very inefficient to
	// allow sloppy SQL that does not ensure just one row!
	conn.purgeResult();
}

/++
Execute an SQL SELECT command or prepared statement and return a single value:
the first column of the first row received.

If the query did not produce any rows, or the rows it produced have zero columns,
this will return `Nullable!MySQLVal()`, ie, null. Test for this with
`result.isNull`.

If the query DID produce a result, but the value actually received is NULL,
then `result.isNull` will be FALSE, and `result.get` will produce a MySQLVal
which CONTAINS null. Check for this with `result.get.kind == MySQLVal.Kind.Null`
or `result.get == null`.

If the SQL command does not produce a result set (such as INSERT/CREATE/etc),
then `mysql.exceptions.MYXNoResultRecieved` will be thrown. Use
`exec` instead for such commands.

If `args` is supplied, the sql string will automatically be used as a prepared
statement. Prepared statements are automatically cached by mysql-native,
so there's no performance penalty for using this multiple times for the
same statement instead of manually preparing a statement.

If `args` and `prepared` are both provided, `args` will be used,
and any arguments that are already set in the prepared statement
will automatically be replaced with `args` (note, just like calling
`mysql.impl.prepared.SafePrepared.setArgs`, this will also remove all
`mysql.impl.prepared.SafeParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.impl.prepared.SafeParameterSpecialization`, use
`mysql.safe.connection.prepare` to manually create a `mysql.impl.prepared.SafePrepared`,
and set your parameter specializations using `mysql.impl.prepared.SafePrepared.setArg`
or `mysql.impl.prepared.SafePrepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.impl.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.

Returns: `Nullable!MySQLVal`: This will be null (check via `Nullable.isNull`) if the
query resulted in an empty result set.

Example:
---
auto myInt = 7;
Nullable!MySQLVal value = myConnection.queryRow("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
---
+/
/+
Future text:
If there are long data items among the expected result columns you can use
the `csa` param to specify that they are to be subject to chunked transfer via a
delegate.

csa = An optional array of `ColumnSpecialization` structs. If you need to
use this with a prepared statement, please use `mysql.prepared.Prepared.columnSpecials`.
+/
/+
Future text:
If there are long data items among the expected result columns you can use
the `csa` param to specify that they are to be subject to chunked transfer via a
delegate.

csa = An optional array of `ColumnSpecialization` structs. If you need to
use this with a prepared statement, please use `mysql.prepared.Prepared.columnSpecials`.
+/
Nullable!MySQLVal queryValue(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null)
{
	return queryValueImpl(csa, conn, ExecQueryImplInfo(false, sql));
}
///ditto
Nullable!MySQLVal queryValue(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!MySQLVal queryValue(Connection conn, const(char[]) sql, MySQLVal[] args)
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!MySQLVal queryValue(Connection conn, ref Prepared prepared)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	auto result = queryValueImpl(prepared.columnSpecials, conn, prepared.getExecQueryImplInfo(preparedInfo.statementId));
	prepared._lastInsertID = conn.lastInsertID; // Conceivably, this might be needed when multi-statements are enabled.
	return result;
}
///ditto
Nullable!MySQLVal queryValue(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!MySQLVal queryValue(Connection conn, ref Prepared prepared, MySQLVal[] args)
{
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}

/// Common implementation for `queryValue` overloads.
package Nullable!MySQLVal queryValueImpl(ColumnSpecialization[] csa, Connection conn,
	ExecQueryImplInfo info)
{
	auto results = queryImpl(csa, conn, info);
	if(results.empty)
		return Nullable!MySQLVal();
	else
	{
		auto row = results.front;
		results.close();

		if(row.length == 0)
			return Nullable!MySQLVal();
		else
			return Nullable!MySQLVal(row[0]);
	}
}

