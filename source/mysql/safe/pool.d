module mysql.safe.pool;

import mysql.internal.pool;
// need to check if mysqlpool was enabled
static if(__traits(compiles, () { alias p = MySQLPoolImpl!true; }))
	alias MySQLPool = MySQLPoolImpl!true;
