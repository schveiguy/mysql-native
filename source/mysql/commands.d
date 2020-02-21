/++
This module publicly imports `mysql.unsafe.commands`, which provides the
Variant-based interface to mysql. In the future, this will switch to importing the
`mysql.safe.commands`, which provides the @safe interface to mysql. Please see
those two modules for documentation on the functions provided. It is highly
recommended to import `mysql.safe.commands` and not the unsafe commands, as
that is the future for mysql-native.

In the far future, the unsafe version will be deprecated and removed, and the
safe version moved to this location.

$(SAFE_MIGRATION)
+/
module mysql.commands;
public import mysql.unsafe.commands;
