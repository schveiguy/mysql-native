/++
Use a DB via plain SQL statements (unsafe version).

Commands that are expected to return a result set - queries - have distinctive
methods that are enforced. That is it will be an error to call such a method
with an SQL command that does not produce a result set. So for commands like
SELECT, use the `query` functions. For other commands, like
INSERT/UPDATE/CREATE/etc, use `exec`.

This is the @system version of mysql's command module, and as such uses the @system
rows and result ranges, and the `Variant` type. For the `MySQLVal` safe
version, please import `mysql.safe.commands`.
+/

module mysql.unsafe.commands;
import SC = mysql.safe.commands;

import std.conv;
import std.exception;
import std.range;
import std.typecons;
import std.variant;

import mysql.unsafe.connection;
import mysql.exceptions;
import mysql.unsafe.prepared;
import mysql.protocol.comms;
import mysql.protocol.constants;
import mysql.protocol.extra_types;
import mysql.protocol.packets;
import mysql.impl.result;
import mysql.types;

alias ColumnSpecialization = SC.ColumnSpecialization;
alias CSN = ColumnSpecialization;

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
`mysql.prepared.Prepared.setArgs`, this will also remove all
`mysql.prepared.ParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.prepared.ParameterSpecialization`, use
`mysql.connection.prepare` to manually create a `mysql.prepared.Prepared`,
and set your parameter specializations using `mysql.prepared.Prepared.setArg`
or `mysql.prepared.Prepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.

Returns: The number of rows affected.

Example:
---
auto myInt = 7;
auto rowsAffected = myConnection.exec("INSERT INTO `myTable` (`a`) VALUES (?)", myInt);
---
+/
ulong exec(Connection conn, const(char[]) sql, Variant[] args) @system
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return exec(conn, prepared);
}
///ditto
ulong exec(Connection conn, ref Prepared prepared, Variant[] args) @system
{
	prepared.setArgs(args);
	return exec(conn, prepared);
}

///ditto
ulong exec(Connection conn, ref BackwardCompatPrepared prepared) @system
{
	auto p = prepared.prepared;
	auto result = exec(conn, p);
	prepared._prepared = p;
	return result;
}

///ditto
ulong exec(Connection conn, ref Prepared prepared) @system
{
	return SC.exec(conn, prepared.safeForExec);
}

///ditto
ulong exec(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]))
{
	// we are about to set all args, which will clear any parameter specializations.
	prepared.setArgs(args);
	return SC.exec(conn, prepared.safe);
}

// Note: this is a wrapper for the safe commands exec functions that do not
// involve a Prepared struct directly.
///ditto
@safe ulong exec(T...)(Connection conn, const(char[]) sql, T args)
	if(!is(T[0] == Variant[]))
{
	return SC.exec(conn, sql, args);
}

/++
Execute an SQL SELECT command or prepared statement.

This returns an input range of `mysql.result.UnsafeRow`, so if you need random access
to the `mysql.result.UnsafeRow` elements, simply call
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
`mysql.prepared.Prepared.setArgs`, this will also remove all
`mysql.prepared.ParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.prepared.ParameterSpecialization`, use
`mysql.connection.prepare` to manually create a `mysql.prepared.Prepared`,
and set your parameter specializations using `mysql.prepared.Prepared.setArg`
or `mysql.prepared.Prepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.

Returns: A (possibly empty) `mysql.result.UnsafeResultRange`.

Example:
---
UnsafeResultRange oneAtATime = myConnection.query("SELECT * from `myTable`");
UnsafeRow[]       allAtOnce  = myConnection.query("SELECT * from `myTable`").array;

auto myInt = 7;
UnsafeResultRange rows = myConnection.query("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
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
UnsafeResultRange query(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null) @safe
{
	return SC.query(conn, sql, csa).unsafe;
}
///ditto
UnsafeResultRange query(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return query(conn, prepared);
}
///ditto
UnsafeResultRange query(Connection conn, const(char[]) sql, Variant[] args) @system
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return query(conn, prepared);
}
///ditto
UnsafeResultRange query(Connection conn, ref Prepared prepared) @system
{
	return SC.query(conn, prepared.safeForExec).unsafe;
}
///ditto
UnsafeResultRange query(T...)(Connection conn, ref Prepared prepared, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	// this is going to clear any parameter specialization
	prepared.setArgs(args);
	return SC.query(conn, prepared.safe, args).unsafe;
}
///ditto
UnsafeResultRange query(Connection conn, ref Prepared prepared, Variant[] args) @system
{
	prepared.setArgs(args);
	return query(conn, prepared);
}

///ditto
UnsafeResultRange query(Connection conn, ref BackwardCompatPrepared prepared) @system
{
	auto p = prepared.prepared;
	auto result = query(conn, p);
	prepared._prepared = p;
	return result;
}

/++
Execute an SQL SELECT command or prepared statement where you only want the
first `mysql.result.UnsafeRow`, if any.

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
`mysql.prepared.Prepared.setArgs`, this will also remove all
`mysql.prepared.ParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.prepared.ParameterSpecialization`, use
`mysql.connection.prepare` to manually create a `mysql.prepared.Prepared`,
and set your parameter specializations using `mysql.prepared.Prepared.setArg`
or `mysql.prepared.Prepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.

Returns: `Nullable!(mysql.result.UnsafeRow)`: This will be null (check via `Nullable.isNull`) if the
query resulted in an empty result set.

Example:
---
auto myInt = 7;
Nullable!UnsafeRow row = myConnection.queryRow("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
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
Nullable!UnsafeRow queryRow(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null) @safe
{
	return SC.queryRow(conn, sql, csa).unsafe;
}
///ditto
Nullable!UnsafeRow queryRow(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}
///ditto
Nullable!UnsafeRow queryRow(Connection conn, const(char[]) sql, Variant[] args) @system
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}
///ditto
Nullable!UnsafeRow queryRow(Connection conn, ref Prepared prepared) @system
{
	return SC.queryRow(conn, prepared.safeForExec).unsafe;
}
///ditto
Nullable!UnsafeRow queryRow(T...)(Connection conn, ref Prepared prepared, T args) @system
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	prepared.setArgs(args);
	return SC.queryRow(conn, prepared.safe, args).unsafe;
}
///ditto
Nullable!UnsafeRow queryRow(Connection conn, ref Prepared prepared, Variant[] args) @system
{
	prepared.setArgs(args);
	return queryRow(conn, prepared);
}

///ditto
Nullable!UnsafeRow queryRow(Connection conn, ref BackwardCompatPrepared prepared) @system
{
	auto p = prepared.prepared;
	auto result = queryRow(conn, p);
	prepared._prepared = p;
	return result;
}

/++
Execute an SQL SELECT command or prepared statement where you only want the
first `mysql.result.UnsafeRow`, and place result values into a set of D variables.

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
conn = An open `mysql.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
args = The variables, taken by reference, to receive the values.
+/
void queryRowTuple(T...)(Connection conn, const(char[]) sql, ref T args)
{
	return SC.queryRowTupleImpl(conn, ExecQueryImplInfo(false, sql), args);
}

///ditto
void queryRowTuple(T...)(Connection conn, ref Prepared prepared, ref T args)
{
	auto preparedInfo = conn.registerIfNeeded(prepared.sql);
	SC.queryRowTupleImpl(conn, prepared.safe.getExecQueryImplInfo(preparedInfo.statementId), args);
	prepared.safe._lastInsertID = conn.lastInsertID; // Conceivably, this might be needed when multi-statements are enabled.
}

///ditto
void queryRowTuple(T...)(Connection conn, ref BackwardCompatPrepared prepared, ref T args) @system
{
	auto p = prepared.prepared;
	queryRowTuple(conn, p, args);
	prepared._prepared = p;
}


/++
Execute an SQL SELECT command or prepared statement and return a single value:
the first column of the first row received.

If the query did not produce any rows, or the rows it produced have zero columns,
this will return `Nullable!Variant()`, ie, null. Test for this with `result.isNull`.

If the query DID produce a result, but the value actually received is NULL,
then `result.isNull` will be FALSE, and `result.get` will produce a Variant
which CONTAINS null. Check for this with `result.get.type == typeid(typeof(null))`.

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
`mysql.prepared.Prepared.setArgs`, this will also remove all
`mysql.prepared.ParameterSpecialization` that may have been applied).

Only use the `const(char[]) sql` overload that doesn't take `args`
when you are not going to be using the same
command repeatedly and you are CERTAIN all the data you're sending is properly
escaped. Otherwise, consider using overload that takes a `Prepared`.

If you need to use any `mysql.prepared.ParameterSpecialization`, use
`mysql.connection.prepare` to manually create a `mysql.prepared.Prepared`,
and set your parameter specializations using `mysql.prepared.Prepared.setArg`
or `mysql.prepared.Prepared.setArgs`.

Type_Mappings: $(TYPE_MAPPINGS)

Params:
conn = An open `mysql.connection.Connection` to the database.
sql = The SQL command to be run.
prepared = The prepared statement to be run.
csa = Not yet implemented.

Returns: `Nullable!Variant`: This will be null (check via `Nullable.isNull`) if the
query resulted in an empty result set.

Example:
---
auto myInt = 7;
Nullable!Variant value = myConnection.queryRow("SELECT * FROM `myTable` WHERE `a` = ?", myInt);
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
Nullable!Variant queryValue(Connection conn, const(char[]) sql, ColumnSpecialization[] csa = null) @system
{
	return SC.queryValue(conn, sql, csa).asVariant;
}
///ditto
Nullable!Variant queryValue(T...)(Connection conn, const(char[]) sql, T args)
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}

///ditto
Nullable!Variant queryValue(Connection conn, const(char[]) sql, Variant[] args) @system
{
	auto prepared = conn.prepare(sql);
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!Variant queryValue(Connection conn, ref Prepared prepared) @system
{
	return SC.queryValue(conn, prepared.safeForExec).asVariant;
}
///ditto
Nullable!Variant queryValue(T...)(Connection conn, ref Prepared prepared, T args) @system
	if(T.length > 0 && !is(T[0] == Variant[]) && !is(T[0] == MySQLVal[]) && !is(T[0] == ColumnSpecialization) && !is(T[0] == ColumnSpecialization[]))
{
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!Variant queryValue(Connection conn, ref Prepared prepared, Variant[] args) @system
{
	prepared.setArgs(args);
	return queryValue(conn, prepared);
}
///ditto
Nullable!Variant queryValue(Connection conn, ref BackwardCompatPrepared prepared) @system
{
	auto p = prepared.prepared;
	auto result = queryValue(conn, p);
	prepared._prepared = p;
	return result;
}
