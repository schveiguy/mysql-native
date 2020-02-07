module mysql.unsafe.pool;

import mysql.internal.pool;
// need to check if mysqlpool was enabled
static if(__traits(compiles, () { alias p = MySQLPoolImpl!false; }))
	alias MySQLPool = MySQLPoolImpl!false;
