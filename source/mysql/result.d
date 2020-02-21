/++
This module publicly imports `mysql.unsafe.result`, which provides backwards
compatible structures for processing rows of data from a MySQL server. Please
see that module for details on usage.

It is recommended instead ot import `mysql.safe.result`, which provides
@safe-only mechanisms for processing rows of data.

Note that the actual structs are documented in `mysql.impl.result`.

In the future, this will migrate to importing `mysql.safe.result`. In the far
future, the unsafe version will be deprecated and removed, and the safe version
moved to this location.

$(SAFE_MIGRATION)
++/
module mysql.result;

public import mysql.unsafe.result;
