/// Use a DB via SQL prepared statements.
module mysql.prepared;

import std.exception;
import std.range;
import std.traits;
import std.typecons;
import std.variant;

import mysql.commands;
import mysql.exceptions;
import mysql.protocol.comms;
import mysql.protocol.constants;
import mysql.protocol.packets;
import mysql.result;

/++
A struct to represent specializations of prepared statement parameters.

If you need to send large objects to the database it might be convenient to
send them in pieces. The `chunkSize` and `chunkDelegate` variables allow for this.
If both are provided then the corresponding column will be populated by calling the delegate repeatedly.
The source should fill the indicated slice with data and arrange for the delegate to
return the length of the data supplied (in bytes). If that is less than the `chunkSize`
then the chunk will be assumed to be the last one.
+/
struct ParameterSpecialization
{
	import mysql.protocol.constants;
	
	size_t pIndex;    //parameter number 0 - number of params-1
	SQLType type = SQLType.INFER_FROM_D_TYPE;
	uint chunkSize; /// In bytes
	uint delegate(ubyte[]) chunkDelegate;
}
///ditto
alias PSN = ParameterSpecialization;

/++
Encapsulation of a prepared statement.

Create this via the function `mysql.connection.prepare`. Set your arguments (if any) via
the functions provided, and then run the statement by passing it to
`mysql.commands.exec`/`mysql.commands.query`/etc in place of the sql string parameter.

Commands that are expected to return a result set - queries - have distinctive
methods that are enforced. That is it will be an error to call such a method
with an SQL command that does not produce a result set. So for commands like
SELECT, use the `mysql.commands.query` functions. For other commands, like
INSERT/UPDATE/CREATE/etc, use `mysql.commands.exec`.
+/
struct Prepared
{
private:
	const(char)[] _sql;

package:
	ushort _numParams; /// Number of parameters this prepared statement takes
	PreparedStmtHeaders _headers;
	Variant[] _inParams;
	ParameterSpecialization[] _psa;
	ColumnSpecialization[] _columnSpecials;
	ulong _lastInsertID;

	ExecQueryImplInfo getExecQueryImplInfo(uint statementId)
	{
		return ExecQueryImplInfo(true, null, statementId, _headers, _inParams, _psa);
	}
	
public:
	/++
	Constructor. You probably want `mysql.connection.prepare` instead of this.
 	
	Call `mysqln.connection.prepare` instead of this, unless you are creating
	your own transport bypassing `mysql.connection.Connection` entirely.
	The prepared statement must be registered on the server BEFORE this is
	called (which `mysqln.connection.prepare` does).

	Internally, the result of a successful outcome will be a statement handle - an ID -
	for the prepared statement, a count of the parameters required for
	execution of the statement, and a count of the columns that will be present
	in any result set that the command generates.

	The server will then proceed to send prepared statement headers,
	including parameter descriptions, and result set field descriptions,
	followed by an EOF packet.
	+/
	this(const(char[]) sql, PreparedStmtHeaders headers, ushort numParams)
	{
		this._sql        = sql;
		this._headers    = headers;
		this._numParams  = numParams;
		_inParams.length = numParams;
		_psa.length      = numParams;
	}

	/++
	Prepared statement parameter setter.

	The value may, but doesn't have to be, wrapped in a Variant. If so,
	null is handled correctly.
	
	The value may, but doesn't have to be, a pointer to the desired value.

	The value may, but doesn't have to be, wrapped in a Nullable!T. If so,
	null is handled correctly.

	The value can be null.

	Parameter specializations (ie, for chunked transfer) can be added if required.
	If you wish to use chunked transfer (via `psn`), note that you must supply
	a dummy value for `val` that's typed `ubyte[]`. For example: `cast(ubyte[])[]`.
	
	Type_Mappings: $(TYPE_MAPPINGS)

	Params: index = The zero based index
	+/
	void setArg(T)(size_t index, T val, ParameterSpecialization psn = PSN(0, SQLType.INFER_FROM_D_TYPE, 0, null))
		if(!isInstanceOf!(Nullable, T))
	{
		// Now in theory we should be able to check the parameter type here, since the
		// protocol is supposed to send us type information for the parameters, but this
		// capability seems to be broken. This assertion is supported by the fact that
		// the same information is not available via the MySQL C API either. It is up
		// to the programmer to ensure that appropriate type information is embodied
		// in the variant array, or provided explicitly. This sucks, but short of
		// having a client side SQL parser I don't see what can be done.

		enforce!MYX(index < _numParams, "Parameter index out of range.");

		_inParams[index] = val;
		psn.pIndex = index;
		_psa[index] = psn;
	}

	///ditto
	void setArg(T)(size_t index, Nullable!T val, ParameterSpecialization psn = PSN(0, SQLType.INFER_FROM_D_TYPE, 0, null))
	{
		if(val.isNull)
			setArg(index, null, psn);
		else
			setArg(index, val.get(), psn);
	}

	/++
	Bind a tuple of D variables to the parameters of a prepared statement.
	
	You can use this method to bind a set of variables if you don't need any specialization,
	that is chunked transfer is not neccessary.
	
	The tuple must match the required number of parameters, and it is the programmer's
	responsibility to ensure that they are of appropriate types.

	Type_Mappings: $(TYPE_MAPPINGS)
	+/
	void setArgs(T...)(T args)
		if(T.length == 0 || !is(T[0] == Variant[]))
	{
		enforce!MYX(args.length == _numParams, "Argument list supplied does not match the number of parameters.");

		foreach (size_t i, arg; args)
			setArg(i, arg);
	}

	/++
	Bind a Variant[] as the parameters of a prepared statement.
	
	You can use this method to bind a set of variables in Variant form to
	the parameters of a prepared statement.
	
	Parameter specializations (ie, for chunked transfer) can be added if required.
	If you wish to use chunked transfer (via `psn`), note that you must supply
	a dummy value for `val` that's typed `ubyte[]`. For example: `cast(ubyte[])[]`.

	This method could be
	used to add records from a data entry form along the lines of
	------------
	auto stmt = conn.prepare("INSERT INTO `table42` VALUES(?, ?, ?)");
	DataRecord dr;    // Some data input facility
	ulong ra;
	do
	{
	    dr.get();
	    stmt.setArgs(dr("Name"), dr("City"), dr("Whatever"));
	    ulong rowsAffected = conn.exec(stmt);
	} while(!dr.done);
	------------

	Type_Mappings: $(TYPE_MAPPINGS)

	Params:
	args = External list of Variants to be used as parameters
	psnList = Any required specializations
	+/
	void setArgs(Variant[] args, ParameterSpecialization[] psnList=null)
	{
		enforce!MYX(args.length == _numParams, "Param count supplied does not match prepared statement");
		_inParams[] = args[];
		if (psnList !is null)
		{
			foreach (PSN psn; psnList)
				_psa[psn.pIndex] = psn;
		}
	}

	/++
	Prepared statement parameter getter.

	Type_Mappings: $(TYPE_MAPPINGS)

	Params: index = The zero based index
	+/
	Variant getArg(size_t index)
	{
		enforce!MYX(index < _numParams, "Parameter index out of range.");
		return _inParams[index];
	}

	/++
	Sets a prepared statement parameter to NULL.
	
	This is here mainly for legacy reasons. You can set a field to null
	simply by saying `prepared.setArg(index, null);`

	Type_Mappings: $(TYPE_MAPPINGS)

	Params: index = The zero based index
	+/
	void setNullArg(size_t index)
	{
		setArg(index, null);
	}

	/// Gets the SQL command for this prepared statement.
	const(char)[] sql()
	{
		return _sql;
	}

	/// Gets the number of arguments this prepared statement expects to be passed in.
	@property ushort numArgs() pure const nothrow
	{
		return _numParams;
	}

	/// After a command that inserted a row into a table with an auto-increment
	/// ID column, this method allows you to retrieve the last insert ID generated
	/// from this prepared statement.
	@property ulong lastInsertID() pure const nothrow { return _lastInsertID; }

	/// Gets the prepared header's field descriptions.
	@property FieldDescription[] preparedFieldDescriptions() pure { return _headers.fieldDescriptions; }

	/// Gets the prepared header's param descriptions.
	@property ParamDescription[] preparedParamDescriptions() pure { return _headers.paramDescriptions; }

	/// Get/set the column specializations.
	@property ColumnSpecialization[] columnSpecials() pure { return _columnSpecials; }

	///ditto
	@property void columnSpecials(ColumnSpecialization[] csa) pure { _columnSpecials = csa; }
}

/// Template constraint for `PreparedRegistrations`
private enum isPreparedRegistrationsPayload(Payload) =
	__traits(compiles, (){
			static assert(Payload.init.queuedForRelease == false);
			Payload p;
			p.queuedForRelease = true;
		});

debug(MYSQLN_TESTS)
{
	// Test template constraint
	struct TestPreparedRegistrationsBad1 { }
	struct TestPreparedRegistrationsBad2 { bool foo = false; }
	struct TestPreparedRegistrationsBad3 { int queuedForRelease = 1; }
	struct TestPreparedRegistrationsBad4 { bool queuedForRelease = true; }
	struct TestPreparedRegistrationsGood1 { bool queuedForRelease = false; }
	struct TestPreparedRegistrationsGood2 { bool queuedForRelease = false; const(char)[] id; }
	
	static assert(!isPreparedRegistrationsPayload!int);
	static assert(!isPreparedRegistrationsPayload!bool);
	static assert(!isPreparedRegistrationsPayload!TestPreparedRegistrationsBad1);
	static assert(!isPreparedRegistrationsPayload!TestPreparedRegistrationsBad2);
	static assert(!isPreparedRegistrationsPayload!TestPreparedRegistrationsBad3);
	static assert(!isPreparedRegistrationsPayload!TestPreparedRegistrationsBad4);
	//static assert(isPreparedRegistrationsPayload!TestPreparedRegistrationsGood1);
	//static assert(isPreparedRegistrationsPayload!TestPreparedRegistrationsGood2);
}

/++
Common functionality for recordkeeping of prepared statement registration
and queueing for unregister.

Used by `Connection` and `MySQLPool`.

Templated on payload type. The payload should be an aggregate that includes
the field: `bool queuedForRelease = false;`

Allowing access to `directLookup` from other parts of mysql-native IS intentional.
`PreparedRegistrations` isn't intended as 100% encapsulation, it's mainly just
to factor out common functionality needed by both `Connection` and `MySQLPool`.
+/
package struct PreparedRegistrations(Payload)
	if(	isPreparedRegistrationsPayload!Payload)
{
	/++
	Lookup payload by sql string.

	Allowing access to `directLookup` from other parts of mysql-native IS intentional.
	`PreparedRegistrations` isn't intended as 100% encapsulation, it's mainly just
	to factor out common functionality needed by both `Connection` and `MySQLPool`.
	+/
	Payload[const(char[])] directLookup;
	
	/// Returns null if not found
	Nullable!Payload opIndex(const(char[]) sql) pure nothrow
	{
		Nullable!Payload result;
		
		auto pInfo = sql in directLookup;
		if(pInfo)
			result = *pInfo;
		
		return result;
	}

	/// Set `queuedForRelease` flag for a statement in `directLookup`.
	/// Does nothing if statement not in `directLookup`.
	private void setQueuedForRelease(const(char[]) sql, bool value)
	{
		if(auto pInfo = sql in directLookup)
		{
			pInfo.queuedForRelease = value;
			directLookup[sql] = *pInfo;
		}
	}

	/// Queue a prepared statement for release.
	void queueForRelease(const(char[]) sql)
	{
		setQueuedForRelease(sql, true);
	}

	/// Remove a statement from the queue to be released.
	void unqueueForRelease(const(char[]) sql)
	{
		setQueuedForRelease(sql, false);
	}
	
	/// Queues all prepared statements for release.
	void queueAllForRelease()
	{
		foreach(sql, info; directLookup)
			queueForRelease(sql);
	}

	/// Eliminate all records of both registered AND queued-for-release statements.
	void clear()
	{
		static if(__traits(compiles, (){ int[int] aa; aa.clear(); }))
			directLookup.clear();
		else
			directLookup = null;
	}

	/// If already registered, simply returns the cached Payload.
	Payload registerIfNeeded(const(char[]) sql, Payload delegate(const(char[])) doRegister)
	out(info)
	{
		// I'm confident this can't currently happen, but
		// let's make sure that doesn't change.
		assert(!info.queuedForRelease);
	}
	do
	{
		if(auto pInfo = sql in directLookup)
		{
			// The statement is registered. It may, or may not, be queued
			// for release. Either way, all we need to do is make sure it's
			// un-queued and then return.
			pInfo.queuedForRelease = false;
			return *pInfo;
		}

		auto info = doRegister(sql);
		directLookup[sql] = info;

		return info;
	}
}

