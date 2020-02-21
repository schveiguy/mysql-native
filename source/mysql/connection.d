/++
This module publicly imports `mysql.unsafe.connection`, which provides
backwards compatible functions for connecting to a MySQL/MariaDB server.

It is recommended instead to import `mysql.safe.connection`, which provides
@safe-only mechanisms to connect to a database.

Note that the common pieces of the connection are documented and currently
reside in `mysql.impl.connection`. The safe and unsafe portions of the API
reside in `mysql.unsafe.connection` and `mysql.safe.connection` respectively.
Please see these modules for information on using a MySQL `Connection` object.

In the future, this will migrate to importing `mysql.safe.connection`. In the
far future, the unsafe version will be deprecated and removed, and the safe
version moved to this location.

$(SAFE_MIGRATION)
+/
module mysql.connection;

public import mysql.unsafe.connection;
