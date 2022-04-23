module mysql.maintests;
import mysql.test.common;
import mysql.protocol.constants;
import mysql.exceptions;
import mysql.types;

import std.exception;
import std.variant;
import std.typecons;
import std.array;
import std.range;
import std.algorithm;

// mysql.commands
@("columnSpecial")
debug(MYSQLN_TESTS)
unittest
{
	void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands", "connection"));
		mixin(scopedCn);

		// Setup
		cn.exec("DROP TABLE IF EXISTS `columnSpecial`");
		cn.exec("CREATE TABLE `columnSpecial` (
			`data` LONGBLOB
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		immutable totalSize = 1000; // Deliberately not a multiple of chunkSize below
		auto alph = cast(const(ubyte)[]) "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		auto data = alph.cycle.take(totalSize).array;
		cn.exec("INSERT INTO `columnSpecial` VALUES (\""~(cast(const(char)[])data)~"\")");

		// Common stuff
		int chunkSize;
		immutable selectSQL = "SELECT `data` FROM `columnSpecial`";
		ubyte[] received;
		bool lastValueOfFinished;
		void receiver(const(ubyte)[] chunk, bool finished)
		{
			assert(lastValueOfFinished == false);

			if(finished)
				assert(chunk.length == chunkSize);
			else
				assert(chunk.length < chunkSize); // Not always true in general, but true in this unittest

			received ~= chunk;
			lastValueOfFinished = finished;
		}

		// Sanity check
		auto value = cn.queryValue(selectSQL);
		assert(!value.isNull);
		assert(value.get == data);

		// Use ColumnSpecialization with sql string,
		// and totalSize as a multiple of chunkSize
		{
			chunkSize = 100;
			assert(cast(int)(totalSize / chunkSize) * chunkSize == totalSize);
			auto columnSpecial = ColumnSpecialization(0, 0xfc, chunkSize, &receiver);

			received = null;
			lastValueOfFinished = false;
			value = cn.queryValue(selectSQL, [columnSpecial]);
			assert(!value.isNull);
			assert(value.get == data);
			//TODO: ColumnSpecialization is not yet implemented
			//assert(lastValueOfFinished == true);
			//assert(received == data);
		}

		// Use ColumnSpecialization with sql string,
		// and totalSize as a non-multiple of chunkSize
		{
			chunkSize = 64;
			assert(cast(int)(totalSize / chunkSize) * chunkSize != totalSize);
			auto columnSpecial = ColumnSpecialization(0, 0xfc, chunkSize, &receiver);

			received = null;
			lastValueOfFinished = false;
			value = cn.queryValue(selectSQL, [columnSpecial]);
			assert(!value.isNull);
			assert(value.get == data);
			//TODO: ColumnSpecialization is not yet implemented
			//assert(lastValueOfFinished == true);
			//assert(received == data);
		}

		// Use ColumnSpecialization with prepared statement,
		// and totalSize as a multiple of chunkSize
		{
			chunkSize = 100;
			assert(cast(int)(totalSize / chunkSize) * chunkSize == totalSize);
			auto columnSpecial = ColumnSpecialization(0, 0xfc, chunkSize, &receiver);

			received = null;
			lastValueOfFinished = false;
			auto prepared = cn.prepare(selectSQL);
			prepared.columnSpecials = [columnSpecial];
			value = cn.queryValue(prepared);
			assert(!value.isNull);
			assert(value.get == data);
			//TODO: ColumnSpecialization is not yet implemented
			//assert(lastValueOfFinished == true);
			//assert(received == data);
		}
	}

	test!false();
	() @safe { test!true(); } ();
}

// Test what happens when queryRowTuple receives no rows
@("queryRowTuple_noRows")
debug(MYSQLN_TESTS)
unittest
{
	import mysql.safe.commands;
	mixin(scopedCn);

	cn.exec("DROP TABLE IF EXISTS `queryRowTuple_noRows`");
	cn.exec("CREATE TABLE `queryRowTuple_noRows` (
		`val` INTEGER
	) ENGINE=InnoDB DEFAULT CHARSET=utf8");

	immutable selectSQL = "SELECT * FROM `queryRowTuple_noRows`";
	int queryTupleResult;
	assertThrown!MYX(cn.queryRowTuple(selectSQL, queryTupleResult));
}

@("execOverloads")
debug(MYSQLN_TESTS)
unittest
{
	void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "commands"));
		mixin(scopedCn);
		static if(doSafe)
			alias MYVAL = MySQLVal;
		else
			alias MYVAL = Variant;

		cn.exec("DROP TABLE IF EXISTS `execOverloads`");
		cn.exec("CREATE TABLE `execOverloads` (
			`i` INTEGER,
			`s` VARCHAR(50)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		immutable prepareSQL = "INSERT INTO `execOverloads` VALUES (?, ?)";

		// Do the inserts, using exec

		// exec: const(char[]) sql
		assert(cn.exec("INSERT INTO `execOverloads` VALUES (1, \"aa\")") == 1);
		assert(cn.exec(prepareSQL, 2, "bb") == 1);
		assert(cn.exec(prepareSQL, [MYVAL(3), MYVAL("cc")]) == 1);

		// exec: prepared sql
		auto prepared = cn.prepare(prepareSQL);
		prepared.setArgs(4, "dd");
		assert(cn.exec(prepared) == 1);

		assert(cn.exec(prepared, 5, "ee") == 1);
		assert(prepared.getArg(0) == 5);
		assert(prepared.getArg(1) == "ee");

		assert(cn.exec(prepared, [MYVAL(6), MYVAL("ff")]) == 1);
		assert(prepared.getArg(0) == 6);
		assert(prepared.getArg(1) == "ff");

		// exec: bcPrepared sql
		auto bcPrepared = cn.prepareBackwardCompatImpl(prepareSQL);
		static assert(doSafe || is(typeof(bcPrepared) == BackwardCompatPrepared));
		bcPrepared.setArgs(7, "gg");
		assert(cn.exec(bcPrepared) == 1);
		assert(bcPrepared.getArg(0) == 7);
		assert(bcPrepared.getArg(1) == "gg");

		// Check results
		auto rows = cn.query("SELECT * FROM `execOverloads`").array();
		assert(rows.length == 7);

		assert(rows[0].length == 2);
		assert(rows[1].length == 2);
		assert(rows[2].length == 2);
		assert(rows[3].length == 2);
		assert(rows[4].length == 2);
		assert(rows[5].length == 2);
		assert(rows[6].length == 2);

		assert(rows[0][0] == 1);
		assert(rows[0][1] == "aa");
		assert(rows[1][0] == 2);
		assert(rows[1][1] == "bb");
		assert(rows[2][0] == 3);
		assert(rows[2][1] == "cc");
		assert(rows[3][0] == 4);
		assert(rows[3][1] == "dd");
		assert(rows[4][0] == 5);
		assert(rows[4][1] == "ee");
		assert(rows[5][0] == 6);
		assert(rows[5][1] == "ff");
		assert(rows[6][0] == 7);
		assert(rows[6][1] == "gg");
	}
	test!false();
	() @safe { test!true(); } ();
}

@("queryOverloads")
debug(MYSQLN_TESTS)
unittest
{
	void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "commands", "result"));
		mixin(scopedCn);
		static if(doSafe)
			alias MYVAL = MySQLVal;
		else
			alias MYVAL = Variant;

		cn.exec("DROP TABLE IF EXISTS `queryOverloads`");
		cn.exec("CREATE TABLE `queryOverloads` (
			`i` INTEGER,
			`s` VARCHAR(50)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `queryOverloads` VALUES (1, \"aa\"), (2, \"bb\"), (3, \"cc\")");

		immutable prepareSQL = "SELECT * FROM `queryOverloads` WHERE `i`=? AND `s`=?";

		// Test query
		{
			Row[] rows;

			// String sql
			rows = cn.query("SELECT * FROM `queryOverloads` WHERE `i`=1 AND `s`=\"aa\"").array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 1);
			assert(rows[0][1] == "aa");

			rows = cn.query(prepareSQL, 2, "bb").array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 2);
			assert(rows[0][1] == "bb");

			rows = cn.query(prepareSQL, [MYVAL(3), MYVAL("cc")]).array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 3);
			assert(rows[0][1] == "cc");

			// Prepared sql
			auto prepared = cn.prepare(prepareSQL);
			prepared.setArgs(1, "aa");
			rows = cn.query(prepared).array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 1);
			assert(rows[0][1] == "aa");

			rows = cn.query(prepared, 2, "bb").array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 2);
			assert(rows[0][1] == "bb");

			rows = cn.query(prepared, [MYVAL(3), MYVAL("cc")]).array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 3);
			assert(rows[0][1] == "cc");

			// BCPrepared sql
			auto bcPrepared = cn.prepareBackwardCompatImpl(prepareSQL);
			static assert(doSafe || is(typeof(bcPrepared) == BackwardCompatPrepared));
			bcPrepared.setArgs(1, "aa");
			rows = cn.query(bcPrepared).array;
			assert(rows.length == 1);
			assert(rows[0].length == 2);
			assert(rows[0][0] == 1);
			assert(rows[0][1] == "aa");
		}

		// Test queryRow
		{
			// Note, queryRow returns Nullable, but we always expect to get a row,
			// so we will let the `get` check in Nullable assert that it's not
			// null.
			Row row;

			// String sql
			row = cn.queryRow("SELECT * FROM `queryOverloads` WHERE `i`=1 AND `s`=\"aa\"").get;
			assert(row.length == 2);
			assert(row[0] == 1);
			assert(row[1] == "aa");

			row = cn.queryRow(prepareSQL, 2, "bb").get;
			assert(row.length == 2);
			assert(row[0] == 2);
			assert(row[1] == "bb");

			row = cn.queryRow(prepareSQL, [MYVAL(3), MYVAL("cc")]).get;
			assert(row.length == 2);
			assert(row[0] == 3);
			assert(row[1] == "cc");

			// Prepared sql
			auto prepared = cn.prepare(prepareSQL);
			prepared.setArgs(1, "aa");
			row = cn.queryRow(prepared).get;
			assert(row.length == 2);
			assert(row[0] == 1);
			assert(row[1] == "aa");

			row = cn.queryRow(prepared, 2, "bb").get;
			assert(row.length == 2);
			assert(row[0] == 2);
			assert(row[1] == "bb");

			row = cn.queryRow(prepared, [MYVAL(3), MYVAL("cc")]).get;
			assert(row.length == 2);
			assert(row[0] == 3);
			assert(row[1] == "cc");

			// BCPrepared sql
			auto bcPrepared = cn.prepareBackwardCompatImpl(prepareSQL);
			static assert(doSafe || is(typeof(bcPrepared) == BackwardCompatPrepared));
			bcPrepared.setArgs(1, "aa");
			row = cn.queryRow(bcPrepared).get;
			assert(row.length == 2);
			assert(row[0] == 1);
			assert(row[1] == "aa");
		}

		// Test queryRowTuple
		{
			int i;
			string s;

			// String sql
			cn.queryRowTuple("SELECT * FROM `queryOverloads` WHERE `i`=1 AND `s`=\"aa\"", i, s);
			assert(i == 1);
			assert(s == "aa");

			// Prepared sql
			auto prepared = cn.prepare(prepareSQL);
			prepared.setArgs(2, "bb");
			cn.queryRowTuple(prepared, i, s);
			assert(i == 2);
			assert(s == "bb");

			// BCPrepared sql
			auto bcPrepared = cn.prepareBackwardCompatImpl(prepareSQL);
			static assert(doSafe || is(typeof(bcPrepared) == BackwardCompatPrepared));
			bcPrepared.setArgs(3, "cc");
			cn.queryRowTuple(bcPrepared, i, s);
			assert(i == 3);
			assert(s == "cc");
		}

		// Test queryValue
		{
			MYVAL value;

			// String sql
			value = cn.queryValue("SELECT * FROM `queryOverloads` WHERE `i`=1 AND `s`=\"aa\"").get;
			assert(!value.valIsNull);
			assert(value == 1);

			value = cn.queryValue(prepareSQL, 2, "bb").get;
			assert(!value.valIsNull);
			assert(value == 2);

			value = cn.queryValue(prepareSQL, [MYVAL(3), MYVAL("cc")]).get;
			assert(!value.valIsNull);
			assert(value == 3);

			// Prepared sql
			auto prepared = cn.prepare(prepareSQL);
			prepared.setArgs(1, "aa");
			value = cn.queryValue(prepared).get;
			assert(!value.valIsNull);
			assert(value == 1);

			value = cn.queryValue(prepared, 2, "bb").get;
			assert(!value.valIsNull);
			assert(value == 2);

			value = cn.queryValue(prepared, [MYVAL(3), MYVAL("cc")]).get;
			assert(!value.valIsNull);
			assert(value == 3);

			// BCPrepared sql
			auto bcPrepared = cn.prepareBackwardCompatImpl(prepareSQL);
			static assert(doSafe || is(typeof(bcPrepared) == BackwardCompatPrepared));
			bcPrepared.setArgs(1, "aa");
			value = cn.queryValue(bcPrepared).get;
			assert(!value.valIsNull);
			assert(value == 1);
		}
	}
	test!false();
	() @safe { test!true(); } ();
}

// mysql.connection
@("prepareFunction")
debug(MYSQLN_TESTS)
unittest
{
	import mysql.safe.connection;
	import mysql.safe.commands;
	mixin(scopedCn);

	exec(cn, `DROP FUNCTION IF EXISTS hello`);
	exec(cn, `
		CREATE FUNCTION hello (s CHAR(20))
		RETURNS CHAR(50) DETERMINISTIC
		RETURN CONCAT('Hello ',s,'!')
	`);

	auto preparedHello = prepareFunction(cn, "hello", 1);
	preparedHello.setArgs("World");
	auto rs = cn.query(preparedHello).array;
	assert(rs.length == 1);
	assert(rs[0][0] == "Hello World!");
}

@("prepareProcedure")
debug(MYSQLN_TESTS)
unittest
{
	import mysql.test.integration;
	import mysql.safe.connection;
	import mysql.safe.commands;
	mixin(scopedCn);
	initBaseTestTables!true(cn);

	exec(cn, `DROP PROCEDURE IF EXISTS insert2`);
	exec(cn, `
		CREATE PROCEDURE insert2 (IN p1 INT, IN p2 CHAR(50))
		BEGIN
			INSERT INTO basetest (intcol, stringcol) VALUES(p1, p2);
		END
	`);

	auto preparedInsert2 = prepareProcedure(cn, "insert2", 2);
	preparedInsert2.setArgs(2001, "inserted string 1");
	cn.exec(preparedInsert2);

	auto rs = query(cn, "SELECT stringcol FROM basetest WHERE intcol=2001").array;
	assert(rs.length == 1);
	assert(rs[0][0] == "inserted string 1");
}

// This also serves as a regression test for #167:
// ResultRange doesn't get invalidated upon reconnect
@("reconnect")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands"));
		mixin(scopedCn);
		cn.exec("DROP TABLE IF EXISTS `reconnect`");
		cn.exec("CREATE TABLE `reconnect` (a INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `reconnect` VALUES (1),(2),(3)");

		enum sql = "SELECT a FROM `reconnect`";

		// Sanity check
		auto rows = cn.query(sql).array;
		assert(rows[0][0] == 1);
		assert(rows[1][0] == 2);
		assert(rows[2][0] == 3);

		// Ensure reconnect keeps the same connection when it's supposed to
		auto range = cn.query(sql);
		assert(range.front[0] == 1);
		cn.reconnect();
		assert(!cn.closed); // Is open?
		assert(range.isValid); // Still valid?
		range.popFront();
		assert(range.front[0] == 2);

		// Ensure reconnect reconnects when it's supposed to
		range = cn.query(sql);
		assert(range.front[0] == 1);
		cn._clientCapabilities = ~cn._clientCapabilities; // Pretend that we're changing the clientCapabilities
		cn.reconnect(~cn._clientCapabilities);
		assert(!cn.closed); // Is open?
		assert(!range.isValid); // Was invalidated?
		cn.query(sql).array; // Connection still works?

		// Try manually reconnecting
		range = cn.query(sql);
		assert(range.front[0] == 1);
		cn.connect(cn._clientCapabilities);
		assert(!cn.closed); // Is open?
		assert(!range.isValid); // Was invalidated?
		cn.query(sql).array; // Connection still works?

		// Try manually closing and connecting
		range = cn.query(sql);
		assert(range.front[0] == 1);
		cn.close();
		assert(cn.closed); // Is closed?
		assert(!range.isValid); // Was invalidated?
		cn.connect(cn._clientCapabilities);
		assert(!cn.closed); // Is open?
		assert(!range.isValid); // Was invalidated?
		cn.query(sql).array; // Connection still works?

		// Auto-reconnect upon a command
		cn.close();
		assert(cn.closed);
		range = cn.query(sql);
		assert(!cn.closed);
		assert(range.front[0] == 1);
	}
	test!false();
	() @safe { test!true(); } ();
}

@("releaseAll")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands", "connection"));
		mixin(scopedCn);

		cn.exec("DROP TABLE IF EXISTS `releaseAll`");
		cn.exec("CREATE TABLE `releaseAll` (a INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		auto preparedSelect = cn.prepare("SELECT * FROM `releaseAll`");
		auto preparedInsert = cn.prepare("INSERT INTO `releaseAll` (a) VALUES (1)");
		assert(cn.isRegistered(preparedSelect));
		assert(cn.isRegistered(preparedInsert));

		cn.releaseAll();
		assert(!cn.isRegistered(preparedSelect));
		assert(!cn.isRegistered(preparedInsert));
		cn.exec("INSERT INTO `releaseAll` (a) VALUES (1)");
		assert(!cn.isRegistered(preparedSelect));
		assert(!cn.isRegistered(preparedInsert));

		cn.exec(preparedInsert);
		cn.query(preparedSelect).array;
		assert(cn.isRegistered(preparedSelect));
		assert(cn.isRegistered(preparedInsert));
	}
	test!false();
	() @safe { test!true(); } ();
}

// Test register, release, isRegistered, and auto-register for prepared statements
@("autoRegistration")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "prepared", "commands"));

		Prepared preparedInsert;
		Prepared preparedSelect;
		immutable insertSQL = "INSERT INTO `autoRegistration` VALUES (1), (2)";
		immutable selectSQL = "SELECT `val` FROM `autoRegistration`";
		int queryTupleResult;

		{
			mixin(scopedCn);

			// Setup
			cn.exec("DROP TABLE IF EXISTS `autoRegistration`");
			cn.exec("CREATE TABLE `autoRegistration` (
													  `val` INTEGER
													 ) ENGINE=InnoDB DEFAULT CHARSET=utf8");

			// Initial register
			preparedInsert = cn.prepare(insertSQL);
			preparedSelect = cn.prepare(selectSQL);

			// Test basic register, release, isRegistered
			assert(cn.isRegistered(preparedInsert));
			assert(cn.isRegistered(preparedSelect));
			cn.release(preparedInsert);
			cn.release(preparedSelect);
			assert(!cn.isRegistered(preparedInsert));
			assert(!cn.isRegistered(preparedSelect));

			// Test manual re-register
			cn.register(preparedInsert);
			cn.register(preparedSelect);
			assert(cn.isRegistered(preparedInsert));
			assert(cn.isRegistered(preparedSelect));

			// Test double register
			cn.register(preparedInsert);
			cn.register(preparedSelect);
			assert(cn.isRegistered(preparedInsert));
			assert(cn.isRegistered(preparedSelect));

			// Test double release
			cn.release(preparedInsert);
			cn.release(preparedSelect);
			assert(!cn.isRegistered(preparedInsert));
			assert(!cn.isRegistered(preparedSelect));
			cn.release(preparedInsert);
			cn.release(preparedSelect);
			assert(!cn.isRegistered(preparedInsert));
			assert(!cn.isRegistered(preparedSelect));
		}

		// Note that at this point, both prepared statements still exist,
		// but are no longer registered on any connection. In fact, there
		// are no open connections anymore.

		// Test auto-register: exec
		{
			mixin(scopedCn);

			assert(!cn.isRegistered(preparedInsert));
			cn.exec(preparedInsert);
			assert(cn.isRegistered(preparedInsert));
		}

		// Test auto-register: query
		{
			mixin(scopedCn);

			assert(!cn.isRegistered(preparedSelect));
			cn.query(preparedSelect).each();
			assert(cn.isRegistered(preparedSelect));
		}

		// Test auto-register: queryRow
		{
			mixin(scopedCn);

			assert(!cn.isRegistered(preparedSelect));
			cn.queryRow(preparedSelect);
			assert(cn.isRegistered(preparedSelect));
		}

		// Test auto-register: queryRowTuple
		{
			mixin(scopedCn);

			assert(!cn.isRegistered(preparedSelect));
			cn.queryRowTuple(preparedSelect, queryTupleResult);
			assert(cn.isRegistered(preparedSelect));
		}

		// Test auto-register: queryValue
		{
			mixin(scopedCn);

			assert(!cn.isRegistered(preparedSelect));
			cn.queryValue(preparedSelect);
			assert(cn.isRegistered(preparedSelect));
		}
	}
	test!false();
	() @safe {test!true(); } ();
}

// An attempt to reproduce issue #81: Using mysql-native driver with no default database
// I'm unable to actually reproduce the error, though.
@("issue81")
debug(MYSQLN_TESTS)
unittest
{
	import std.conv : text;
	static void test(bool doSafe)()
	{
		import mysql.escape;
		mixin(doImports(doSafe, "commands", "connection"));
		mixin(scopedCn);

		cn.exec("DROP TABLE IF EXISTS `issue81`");
		cn.exec("CREATE TABLE `issue81` (a INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `issue81` (a) VALUES (1)");

		auto cn2 = new Connection(text("host=", cn._host, ";port=", cn._port, ";user=", cn._user, ";pwd=", cn._pwd));
		scope(exit) cn2.close();

		cn2.query("SELECT * FROM `"~mysqlEscape(cn._db).text~"`.`issue81`");
	}
	test!false();
	() @safe {test!true(); } ();
}

// Regression test for Issue #154:
// autoPurge can throw an exception if the socket was closed without purging
//
// This simulates a disconnect by closing the socket underneath the Connection
// object itself.
@("dropConnection")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands", "connection", "prepared"));
		mixin(scopedCn);

		cn.exec("DROP TABLE IF EXISTS `dropConnection`");
		cn.exec("CREATE TABLE `dropConnection` (
												`val` INTEGER
											   ) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `dropConnection` VALUES (1), (2), (3)");
		{
			auto prep = cn.prepare("SELECT * FROM `dropConnection`");
			cn.query(prep);
		}
		// close the socket forcibly
		cn._socket.close();
		// this should still work (it should reconnect).
		cn.exec("DROP TABLE `dropConnection`");
	}

	test!false();
	() @safe {test!true(); } ();
}

/+
Test Prepared's ability to be safely refcount-released during a GC cycle
(ie, `Connection.release` must not allocate GC memory).

Currently disabled because it's not guaranteed to always work
(and apparently, cannot be made to work?)
For relevant discussion, see issue #159:
https://github.com/mysql-d/mysql-native/issues/159
+/
version(none)
debug(MYSQLN_TESTS)
{
	/// Proof-of-concept ref-counted Prepared wrapper, just for testing,
	/// not really intended for actual use.
	private struct RCPreparedPayload
	{
		Prepared prepared;
		Connection conn; // Connection to be released from

		alias prepared this;

		@disable this(this); // not copyable
		~this()
		{
			// There are a couple calls to this dtor where `conn` happens to be null.
			if(conn is null)
				return;

			assert(conn.isRegistered(prepared));
			conn.release(prepared);
		}
	}
	///ditto
	alias RCPrepared = RefCounted!(RCPreparedPayload, RefCountedAutoInitialize.no);
	///ditto
	private RCPrepared rcPrepare(Connection conn, const(char[]) sql)
	{
		auto prepared = conn.prepare(sql);
		auto payload = RCPreparedPayload(prepared, conn);
		return refCounted(move(payload));
	}

	@("rcPrepared")
	unittest
	{
		import core.memory;
		mixin(scopedCn);

		cn.exec("DROP TABLE IF EXISTS `rcPrepared`");
		cn.exec("CREATE TABLE `rcPrepared` (
			`val` INTEGER
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `rcPrepared` VALUES (1), (2), (3)");

		// Define this in outer scope to guarantee data is left pending when
		// RCPrepared's payload is collected. This will guarantee
		// that Connection will need to queue the release.
		ResultRange rows;

		void bar()
		{
			class Foo { RCPrepared p; }
			auto foo = new Foo();

			auto rcStmt = cn.rcPrepare("SELECT * FROM `rcPrepared`");
			foo.p = rcStmt;
			rows = cn.query(rcStmt);

			/+
			At this point, there are two references to the prepared statement:
			One in a `Foo` object (currently bound to `foo`), and one on the stack.

			Returning from this function will destroy the one on the stack,
			and deterministically reduce the refcount to 1.

			So, right here we set `foo` to null to *keep* the Foo object's
			reference to the prepared statement, but set adrift the Foo object
			itself, ready to be destroyed (along with the only remaining
			prepared statement reference it contains) by the next GC cycle.

			Thus, `RCPreparedPayload.~this` and `Connection.release(Prepared)`
			will be executed during a GC cycle...and had better not perform
			any allocations, or else...boom!
			+/
			foo = null;
		}

		bar();
		assert(cn.hasPending); // Ensure Connection is forced to queue the release.
		GC.collect(); // `Connection.release(Prepared)` better not be allocating, or boom!
	}
}

// mysql.exceptions
@("wrongFunctionException")
debug(MYSQLN_TESTS)
unittest
{
	import mysql.safe.commands;
	import mysql.safe.connection;
	import mysql.safe.prepared;
	mixin(scopedCn);

	cn.exec("DROP TABLE IF EXISTS `wrongFunctionException`");
	cn.exec("CREATE TABLE `wrongFunctionException` (
		`val` INTEGER
	) ENGINE=InnoDB DEFAULT CHARSET=utf8");

	immutable insertSQL = "INSERT INTO `wrongFunctionException` VALUES (1), (2)";
	immutable selectSQL = "SELECT * FROM `wrongFunctionException`";
	Prepared preparedInsert;
	Prepared preparedSelect;
	int queryTupleResult;
	assertNotThrown!MYXWrongFunction(cn.exec(insertSQL));
	assertNotThrown!MYXWrongFunction(cn.query(selectSQL).each());
	assertNotThrown!MYXWrongFunction(cn.queryRowTuple(selectSQL, queryTupleResult));
	assertNotThrown!MYXWrongFunction(preparedInsert = cn.prepare(insertSQL));
	assertNotThrown!MYXWrongFunction(preparedSelect = cn.prepare(selectSQL));
	assertNotThrown!MYXWrongFunction(cn.exec(preparedInsert));
	assertNotThrown!MYXWrongFunction(cn.query(preparedSelect).each());
	assertNotThrown!MYXWrongFunction(cn.queryRowTuple(preparedSelect, queryTupleResult));

	assertThrown!MYXResultRecieved(cn.exec(selectSQL));
	assertThrown!MYXNoResultRecieved(cn.query(insertSQL).each());
	assertThrown!MYXNoResultRecieved(cn.queryRowTuple(insertSQL, queryTupleResult));
	assertThrown!MYXResultRecieved(cn.exec(preparedSelect));
	assertThrown!MYXNoResultRecieved(cn.query(preparedInsert).each());
	assertThrown!MYXNoResultRecieved(cn.queryRowTuple(preparedInsert, queryTupleResult));
}

// mysql.pool
version(Have_vibe_core)
{
	@("onNewConnection")
	debug(MYSQLN_TESTS)
	unittest
	{
		static void test(bool doSafe)()
		{
			mixin(doImports(doSafe, "pool", "connection"));
			auto count = 0;
			void callback(Connection conn)
			{
				count++;
			}

			// Test getting/setting
			auto poolA = new MySQLPool(testConnectionStr, &callback);
			auto poolB = new MySQLPool(testConnectionStr);
			auto poolNoCallback = new MySQLPool(testConnectionStr);

			assert(poolA.onNewConnection == &callback);
			assert(poolB.onNewConnection is null);
			assert(poolNoCallback.onNewConnection is null);

			poolB.onNewConnection = &callback;
			assert(poolB.onNewConnection == &callback);
			assert(count == 0);

			// Ensure callback is called
			{
				auto connA = poolA.lockConnection();
				assert(!connA.closed);
				assert(count == 1);

				auto connB = poolB.lockConnection();
				assert(!connB.closed);
				assert(count == 2);
			}

			// Ensure works with no callback
			{
				auto oldCount = count;
				auto poolC = new MySQLPool(testConnectionStr);
				auto connC = poolC.lockConnection();
				assert(!connC.closed);
				assert(count == oldCount);
			}
		}
		test!false();
		() @safe {test!true(); } ();
	}

	@("registration")
	debug(MYSQLN_TESTS)
	unittest
	{
		static void test(bool doSafe)()
		{
			mixin(doImports(doSafe, "pool", "commands", "connection"));
			auto pool = new MySQLPool(testConnectionStr);

			// Setup
			auto cn = pool.lockConnection();
			cn.exec("DROP TABLE IF EXISTS `poolRegistration`");
			cn.exec("CREATE TABLE `poolRegistration` (
													  `data` LONGBLOB
													 ) ENGINE=InnoDB DEFAULT CHARSET=utf8");
			immutable sql = "SELECT * from `poolRegistration`";
			auto cn2 = pool.lockConnection();
			pool.applyAuto(cn2);
			assert(cn !is cn2);

			// Tests:
			// Initial
			assert(pool.isAutoCleared(sql));
			assert(pool.isAutoRegistered(sql));
			assert(pool.isAutoReleased(sql));
			assert(!cn.isRegistered(sql));
			assert(!cn2.isRegistered(sql));

			// Register on connection #1
			auto prepared = cn.prepare(sql);
			{
				assert(pool.isAutoCleared(sql));
				assert(pool.isAutoRegistered(sql));
				assert(pool.isAutoReleased(sql));
				assert(cn.isRegistered(sql));
				assert(!cn2.isRegistered(sql));

				auto cn3 = pool.lockConnection();
				pool.applyAuto(cn3);
				assert(!cn3.isRegistered(sql));
			}

			// autoRegister
			pool.autoRegister(prepared);
			{
				assert(!pool.isAutoCleared(sql));
				assert(pool.isAutoRegistered(sql));
				assert(!pool.isAutoReleased(sql));
				assert(cn.isRegistered(sql));
				assert(!cn2.isRegistered(sql));

				auto cn3 = pool.lockConnection();
				pool.applyAuto(cn3);
				assert(cn3.isRegistered(sql));
			}

			// autoRelease
			pool.autoRelease(prepared);
			{
				assert(!pool.isAutoCleared(sql));
				assert(!pool.isAutoRegistered(sql));
				assert(pool.isAutoReleased(sql));
				assert(cn.isRegistered(sql));
				assert(!cn2.isRegistered(sql));

				auto cn3 = pool.lockConnection();
				pool.applyAuto(cn3);
				assert(!cn3.isRegistered(sql));
			}

			// clearAuto
			pool.clearAuto(prepared);
			{
				assert(pool.isAutoCleared(sql));
				assert(pool.isAutoRegistered(sql));
				assert(pool.isAutoReleased(sql));
				assert(cn.isRegistered(sql));
				assert(!cn2.isRegistered(sql));

				auto cn3 = pool.lockConnection();
				pool.applyAuto(cn3);
				assert(!cn3.isRegistered(sql));
			}
		}

		test!false();
		() @safe {test!true(); } ();
	}

	@("closedConnection") // "cct"
	debug(MYSQLN_TESTS)
	unittest
	{
		static void test(bool doSafe)()
		{
			mixin(doImports(doSafe, "pool", "commands", "connection"));
			MySQLPool cctPool;
			int cctCount=0;

			void cctStart()
			{

				cctPool = new MySQLPool(testConnectionStr);
				cctPool.onNewConnection = (Connection conn) { cctCount++; };
				assert(cctCount == 0);

				auto cn = cctPool.lockConnection();
				assert(!cn.closed);
				cn.close();
				assert(cn.closed);
				assert(cctCount == 1);
			}

			{
				cctStart();
				assert(cctCount == 1);

				auto cn = cctPool.lockConnection();
				assert(cctCount == 1);
				assert(!cn.closed);
			}
		}

		test!false();
		() @safe {test!true(); } ();
	}
}

// mysql.prepared
@("paramSpecial")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "commands", "prepared"));
		mixin(scopedCn);

		// Setup
		cn.exec("DROP TABLE IF EXISTS `paramSpecial`");
		cn.exec("CREATE TABLE `paramSpecial` (
											  `data` LONGBLOB
											 ) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		immutable totalSize = 1000; // Deliberately not a multiple of chunkSize below
		auto alph = cast(const(ubyte)[]) "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		auto data = alph.cycle.take(totalSize).array;

		int chunkSize;
		const(ubyte)[] dataToSend;
		bool finished;
		uint sender(ubyte[] chunk)
		{
			assert(!finished);
			assert(chunk.length == chunkSize);

			if(dataToSend.length < chunkSize)
			{
				auto actualSize = cast(uint) dataToSend.length;
				chunk[0..actualSize] = dataToSend[];
				finished = true;
				dataToSend.length = 0;
				return actualSize;
			}
			else
			{
				chunk[] = dataToSend[0..chunkSize];
				dataToSend = dataToSend[chunkSize..$];
				return chunkSize;
			}
		}

		immutable selectSQL = "SELECT `data` FROM `paramSpecial`";

		// Sanity check
		cn.exec("INSERT INTO `paramSpecial` VALUES (\""~(cast(const(char)[])data)~"\")");
		auto value = cn.queryValue(selectSQL);
		assert(!value.isNull);
		assert(value.get == data);

		{
			// Clear table
			cn.exec("DELETE FROM `paramSpecial`");
			value = cn.queryValue(selectSQL); // Ensure deleted
			assert(value.isNull);

			// Test: totalSize as a multiple of chunkSize
			chunkSize = 100;
			assert(cast(int)(totalSize / chunkSize) * chunkSize == totalSize);
			auto paramSpecial = ParameterSpecialization(0, SQLType.INFER_FROM_D_TYPE, chunkSize, &sender);

			finished = false;
			dataToSend = data;
			auto prepared = cn.prepare("INSERT INTO `paramSpecial` VALUES (?)");
			prepared.setArg(0, cast(ubyte[])[], paramSpecial);
			assert(cn.exec(prepared) == 1);
			value = cn.queryValue(selectSQL);
			assert(!value.isNull);
			assert(value.get == data);
		}

		{
			// Clear table
			cn.exec("DELETE FROM `paramSpecial`");
			value = cn.queryValue(selectSQL); // Ensure deleted
			assert(value.isNull);

			// Test: totalSize as a non-multiple of chunkSize
			chunkSize = 64;
			assert(cast(int)(totalSize / chunkSize) * chunkSize != totalSize);
			auto paramSpecial = ParameterSpecialization(0, SQLType.INFER_FROM_D_TYPE, chunkSize, &sender);

			finished = false;
			dataToSend = data;
			auto prepared = cn.prepare("INSERT INTO `paramSpecial` VALUES (?)");
			prepared.setArg(0, cast(ubyte[])[], paramSpecial);
			assert(cn.exec(prepared) == 1);
			value = cn.queryValue(selectSQL);
			assert(!value.isNull);
			assert(value.get == data);
		}
	}
	test!false();
	() @safe {test!true(); } ();
}

@("setArg-typeMods")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands"));
		mixin(scopedCn);

		// Setup
		cn.exec("DROP TABLE IF EXISTS `setArg-typeMods`");
		cn.exec("CREATE TABLE `setArg-typeMods` (
			`i` INTEGER
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		auto insertSQL = "INSERT INTO `setArg-typeMods` VALUES (?)";

		// Sanity check
		{
			int i = 111;
			assert(cn.exec(insertSQL, i) == 1);
			auto value = cn.queryValue("SELECT `i` FROM `setArg-typeMods`");
			assert(!value.isNull);
			assert(value.get == i);
		}

		// Test const(int)
		{
			const(int) i = 112;
			assert(cn.exec(insertSQL, i) == 1);
		}

		// Test immutable(int)
		{
			immutable(int) i = 113;
			assert(cn.exec(insertSQL, i) == 1);
		}

		// Note: Variant doesn't seem to support
		// `shared(T)` or `shared(const(T)`. Only `shared(immutable(T))`.

		// Test shared immutable(int)
		{
			shared immutable(int) i = 113;
			assert(cn.exec(insertSQL, i) == 1);
		}
	}

	test!false();
	() @safe {test!true(); } ();
}

@("setNullArg")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "commands", "result"));
		mixin(scopedCn);

		cn.exec("DROP TABLE IF EXISTS `setNullArg`");
		cn.exec("CREATE TABLE `setNullArg` (
			`val` INTEGER
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		immutable insertSQL = "INSERT INTO `setNullArg` VALUES (?)";
		immutable selectSQL = "SELECT * FROM `setNullArg`";
		auto preparedInsert = cn.prepare(insertSQL);
		assert(preparedInsert.sql == insertSQL);
		Row[] rs;

		{
			Nullable!int nullableInt;
			nullableInt.nullify();
			preparedInsert.setArg(0, nullableInt);
			assert(preparedInsert.getArg(0).valIsNull);
			nullableInt = 7;
			preparedInsert.setArg(0, nullableInt);
			assert(preparedInsert.getArg(0) == 7);

			nullableInt.nullify();
			preparedInsert.setArgs(nullableInt);
			assert(preparedInsert.getArg(0).valIsNull);
			nullableInt = 7;
			preparedInsert.setArgs(nullableInt);
			assert(preparedInsert.getArg(0) == 7);
		}

		preparedInsert.setArg(0, 5);
		cn.exec(preparedInsert);
		rs = cn.query(selectSQL).array;
		assert(rs.length == 1);
		assert(rs[0][0] == 5);

		preparedInsert.setArg(0, null);
		cn.exec(preparedInsert);
		rs = cn.query(selectSQL).array;
		assert(rs.length == 2);
		assert(rs[0][0] == 5);
		assert(rs[1].isNull(0));
		assert(rs[1][0].valIsNull);

		static if(doSafe)
			preparedInsert.setArg(0, MySQLVal(null));
		else
			preparedInsert.setArg(0, Variant(null));
		cn.exec(preparedInsert);
		rs = cn.query(selectSQL).array;
		assert(rs.length == 3);
		assert(rs[0][0] == 5);
		assert(rs[1].isNull(0));
		assert(rs[2].isNull(0));
		assert(rs[1][0].valIsNull);
		assert(rs[2][0].valIsNull);
	}

	test!false();
	() @safe {test!true(); } ();
}

@("lastInsertID")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "connection", "commands"));
		mixin(scopedCn);
		cn.exec("DROP TABLE IF EXISTS `testPreparedLastInsertID`");
		cn.exec("CREATE TABLE `testPreparedLastInsertID` (
				`a` INTEGER NOT NULL AUTO_INCREMENT,
				PRIMARY KEY (a)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8");

		auto stmt = cn.prepare("INSERT INTO `testPreparedLastInsertID` VALUES()");
		cn.exec(stmt);
		assert(stmt.lastInsertID == 1);
		cn.exec(stmt);
		assert(stmt.lastInsertID == 2);
		cn.exec(stmt);
		assert(stmt.lastInsertID == 3);
	}

	test!false();
	() @safe {test!true(); } ();
}

// Test PreparedRegistrations
debug(MYSQLN_TESTS)
{
	import mysql.impl.prepared : PreparedRegistrations,
		   TestPreparedRegistrationsGood1, TestPreparedRegistrationsGood2;
	PreparedRegistrations!TestPreparedRegistrationsGood1 testPreparedRegistrationsGood1;
	PreparedRegistrations!TestPreparedRegistrationsGood2 testPreparedRegistrationsGood2;

	@("PreparedRegistrations")
	unittest
	{
		// Test init
		PreparedRegistrations!TestPreparedRegistrationsGood2 pr;
		assert(pr.directLookup.keys.length == 0);

		void resetData(bool isQueued1, bool isQueued2, bool isQueued3)
		{
			pr.directLookup["1"] = TestPreparedRegistrationsGood2(isQueued1, "1");
			pr.directLookup["2"] = TestPreparedRegistrationsGood2(isQueued2, "2");
			pr.directLookup["3"] = TestPreparedRegistrationsGood2(isQueued3, "3");
			assert(pr.directLookup.keys.length == 3);
		}

		// Test resetData (sanity check)
		resetData(false, true, false);
		assert(pr.directLookup["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr.directLookup["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr.directLookup["3"] == TestPreparedRegistrationsGood2(false, "3"));

		// Test opIndex
		resetData(false, true, false);
		pr.directLookup["1"] = TestPreparedRegistrationsGood2(false, "1");
		pr.directLookup["2"] = TestPreparedRegistrationsGood2(true,  "2");
		pr.directLookup["3"] = TestPreparedRegistrationsGood2(false, "3");
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(false, "3"));
		assert(pr["4"].isNull);

		// Test queueForRelease
		resetData(false, true, false);
		pr.queueForRelease("2");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(false, "3"));

		pr.queueForRelease("3");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(true,  "3"));

		pr.queueForRelease("4");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(true,  "3"));

		// Test unqueueForRelease
		resetData(false, true, false);
		pr.unqueueForRelease("1");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(false, "3"));

		pr.unqueueForRelease("2");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(false, "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(false, "3"));

		pr.unqueueForRelease("4");
		assert(pr.directLookup.keys.length == 3);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(false, "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(false, "3"));

		// Test queueAllForRelease
		resetData(false, true, false);
		pr.queueAllForRelease();
		assert(pr["1"] == TestPreparedRegistrationsGood2(true,  "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(true,  "2"));
		assert(pr["3"] == TestPreparedRegistrationsGood2(true,  "3"));
		assert(pr["4"].isNull);

		// Test clear
		resetData(false, true, false);
		pr.clear();
		assert(pr.directLookup.keys.length == 0);

		// Test registerIfNeeded
		auto doRegister(const(char[]) sql) { return TestPreparedRegistrationsGood2(false, sql); }
		pr.registerIfNeeded("1", &doRegister);
		assert(pr.directLookup.keys.length == 1);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));

		pr.registerIfNeeded("1", &doRegister);
		assert(pr.directLookup.keys.length == 1);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));

		pr.registerIfNeeded("2", &doRegister);
		assert(pr.directLookup.keys.length == 2);
		assert(pr["1"] == TestPreparedRegistrationsGood2(false, "1"));
		assert(pr["2"] == TestPreparedRegistrationsGood2(false, "2"));
	}
}

// mysql.result
@("getName")
debug(MYSQLN_TESTS)
unittest
{
	static void test(bool doSafe)()
	{
		mixin(doImports(doSafe, "commands"));
		mixin(scopedCn);
		cn.exec("DROP TABLE IF EXISTS `row_getName`");
		cn.exec("CREATE TABLE `row_getName` (someValue INTEGER, another INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8");
		cn.exec("INSERT INTO `row_getName` VALUES (1, 2), (3, 4)");

		enum sql = "SELECT another, someValue FROM `row_getName`";

		auto rows = cn.query(sql).array;
		assert(rows.length == 2);
		assert(rows[0][0] == 2);
		assert(rows[0][1] == 1);
		assert(rows[0].getName(0) == "another");
		assert(rows[0].getName(1) == "someValue");
		assert(rows[1][0] == 4);
		assert(rows[1][1] == 3);
		assert(rows[1].getName(0) == "another");
		assert(rows[1].getName(1) == "someValue");
	}

	test!false();
	() @safe {test!true(); } ();
}

// issue 222, set column names when data is null.
@("colNamesForBinary")
debug(MYSQLN_TESTS)
unittest
{
	import mysql.safe.commands;
	mixin(scopedCn);
	// binary mode happens with prepared statements
	auto row = cn.queryRow("SELECT `colname` FROM (SELECT 1 AS `id`, NULL AS `colname`) as `tbl` WHERE `id` = ?", 1);
	assert(row.get[0] == null);
	assert(row.get.getName(0) == "colname");
}
