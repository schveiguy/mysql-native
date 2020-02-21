/++
This module publicly imports `mysql.unsafe.pool`, which provides backwards
compatible functions for using vibe.d's
$(LINK2 http://vibed.org/api/vibe.core.connectionpool/ConnectionPool, ConnectionPool).

Please see the module documentation in `mysql.impl.pool` for more details.

In the future, this will migrate to importing `mysql.safe.pool`. In the far
future, the unsafe version will be deprecated and removed, and the safe version
moved to this location.

$(SAFE_MIGRATION)
+/
module mysql.pool;

public import mysql.unsafe.pool;
