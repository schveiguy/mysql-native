/++
Escape special characters in MySQL strings.

Note, it is strongly recommended to use prepared statements instead of relying
on manual escaping, as prepared statements are always safer, better and more
reliable (see `mysql.prepared`). But if you absolutely must escape manually,
the functionality is provided here.
+/
module mysql.escape;


/++
Simple escape function for dangerous SQL characters

Params:
	input = string to escape
	output = output range to write to
+/
void mysql_escape ( Output, Input ) ( Input input, Output output )
{
	import std.string : translate;

	immutable string[dchar] transTable = [
		'\\' : "\\\\",
		'\'' : "\\'",
		'\0' : "\\0",
		'\n' : "\\n",
		'\r' : "\\r",
		'"'  : "\\\"",
		'\032' : "\\Z"
	];

	translate(input, transTable, null, output);
}


/++
Struct to wrap around an input range so it can be passed to formattedWrite and be
properly escaped without allocating a temporary buffer

Params:
	Input = (Template Param) Type of the input range

Note:
    The delegate is expected to be @safe as of version 3.2.0.
+/
struct MysqlEscape ( Input )
{
	Input input;

	const void toString ( scope void delegate(scope const(char)[]) @safe sink )
	{
		mysql_escape(input, sink);
	}
}

/++
Helper function to easily construct a escape wrapper struct

Params:
	T = (Template Param) Type of the input range
	input = Input to escape
+/
MysqlEscape!(T) mysqlEscape ( T ) ( T input )
{
	return MysqlEscape!(T)(input);
}

@("mysqlEscape")
debug(MYSQLN_TESTS)
@safe unittest
{
	import std.array : appender;

	auto buf = appender!string();

	import std.format : formattedWrite;

	formattedWrite(buf, "%s, %s, %s, mkay?", 1, 2,
			mysqlEscape("\0, \r, \n, \", \\"));

	assert(buf.data() == `1, 2, \0, \r, \n, \", \\, mkay?`);
}
