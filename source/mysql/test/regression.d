﻿/++
This contains regression tests for the issues at:
https://github.com/rejectedsoftware/mysql-native/issues

Regression unittests, like other unittests, are located together with
the units they test.
+/
module mysql.test.regression;

import std.algorithm;
import std.conv;
import std.datetime;
import std.digest.sha;
import std.exception;
import std.range;
import std.socket;
import std.stdio;
import std.string;
import std.traits;
import std.variant;

import mysql.commands;
import mysql.connection;
import mysql.exceptions;
import mysql.prepared;
import mysql.protocol.sockets;
import mysql.result;
import mysql.test.common;

// Issue #40: Decoding LCB value for large feilds
// And likely Issue #18: select varchar - thinks the package is incomplete while it's actually complete
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);
	auto cmd = Command(cn);
	cn.exec("DROP TABLE IF EXISTS `issue40`");
	cn.exec(
		"CREATE TABLE `issue40` (
		`str` varchar(255)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8"
	);

	auto longString = repeat('a').take(251).array().idup;
	cn.exec("INSERT INTO `issue40` VALUES('"~longString~"')");
	cn.query("SELECT * FROM `issue40`");

	cn.exec("DELETE FROM `issue40`");

	longString = repeat('a').take(255).array().idup;
	cn.exec("INSERT INTO `issue40` VALUES('"~longString~"')");
	cn.query("SELECT * FROM `issue40`");
}

// Issue #24: Driver doesn't like BIT
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);
	auto cmd = Command(cn);
	ulong rowsAffected;
	cn.exec("DROP TABLE IF EXISTS `issue24`");
	cn.exec(
		"CREATE TABLE `issue24` (
		`bit` BIT,
		`date` DATE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8"
	);
	
	cn.exec("INSERT INTO `issue24` (`bit`, `date`) VALUES (1, '1970-01-01')");
	cn.exec("INSERT INTO `issue24` (`bit`, `date`) VALUES (0, '1950-04-24')");

	auto stmt = cn.prepare("SELECT `bit`, `date` FROM `issue24` ORDER BY `date` DESC");
	auto results = stmt.query.array;
	assert(results.length == 2);
	assert(results[0][0] == true);
	assert(results[0][1] == Date(1970, 1, 1));
	assert(results[1][0] == false);
	assert(results[1][1] == Date(1950, 4, 24));
}

// Issue #33: TINYTEXT, TEXT, MEDIUMTEXT, LONGTEXT types treated as ubyte[]
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);
	auto cmd = Command(cn);
	cn.exec("DROP TABLE IF EXISTS `issue33`");
	cn.exec(
		"CREATE TABLE `issue33` (
		`text` TEXT,
		`blob` BLOB
		) ENGINE=InnoDB DEFAULT CHARSET=utf8"
	);
	
	cn.exec("INSERT INTO `issue33` (`text`, `blob`) VALUES ('hello', 'world')");

	auto stmt = cn.prepare("SELECT `text`, `blob` FROM `issue33`");
	auto results = stmt.query.array;
	assert(results.length == 1);
	auto pText = results[0][0].peek!string();
	auto pBlob = results[0][1].peek!(ubyte[])();
	assert(pText);
	assert(pBlob);
	assert(*pText == "hello");
	assert(*pBlob == cast(ubyte[])"world".dup);
}

// Issue #39: Unsupported SQL type NEWDECIMAL
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);
	auto rows = cn.query("SELECT SUM(123.456)").array;
	assert(rows.length == 1);
	assert(rows[0][0] == "123.456");
}

// Issue #56: Result set quantity does not equal MySQL rows quantity
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);
	auto cmd = Command(cn);
	cn.exec("DROP TABLE IF EXISTS `issue56`");
	cn.exec("CREATE TABLE `issue56` (a datetime DEFAULT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8");
	
	cn.exec("INSERT INTO `issue56` VALUES
		('2015-03-28 00:00:00')
		,('2015-03-29 00:00:00')
		,('2015-03-31 00:00:00')
		,('2015-03-31 00:00:00')
		,('2015-03-31 00:00:00')
		,('2015-03-31 00:00:00')
		,('2015-04-01 00:00:00')
		,('2015-04-02 00:00:00')
		,('2015-04-03 00:00:00')
		,('2015-04-04 00:00:00')");

	auto stmt = cn.prepare("SELECT a FROM `issue56`");
	auto res = stmt.query.array;
	assert(res.length == 10);
}

// Issue #66: Can't connect when omitting default database
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	auto a = Connection.parseConnectionString(testConnectionStr);

	{
		// Sanity check:
		auto cn = new Connection(a[0], a[1], a[2], a[3], to!ushort(a[4]));
		scope(exit) cn.close();
	}

	{
		// Ensure it works without a default database
		auto cn = new Connection(a[0], a[1], a[2], "", to!ushort(a[4]));
		scope(exit) cn.close();
	}
}

// Issue #117: Server packet out of order when Prepared is destroyed too early
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);

	struct S
	{
		this(ResultRange x) { r = x; } // destroying x kills the range
		ResultRange r;
		alias r this;
	}

	cn.exec("DROP TABLE IF EXISTS `issue117`");
	cn.exec("CREATE TABLE `issue117` (a INTEGER) ENGINE=InnoDB DEFAULT CHARSET=utf8");
	cn.exec("INSERT INTO `issue117` (a) VALUES (1)");

	auto r = cn.query("SELECT * FROM `issue117`");
	assert(!r.empty);

	auto s = S(cn.query("SELECT * FROM `issue117`"));
	assert(!s.empty);
}

// Issue #139: Server packet out of order when Prepared is destroyed too early
debug(MYSQL_INTEGRATION_TESTS)
unittest
{
	mixin(scopedCn);

	// Sanity check
	{
		ResultRange result;

		auto prep = cn.prepare("SELECT ?");
		prep.setArgs("Hello world");
		result = prep.query();

		result.close();
	}
	
	// Should not throw server packet out of order
	{
		ResultRange result;
		{
			auto prep = cn.prepare("SELECT ?");
			prep.setArgs("Hello world");
			result = prep.query();
		}

		result.close();
	}
}
