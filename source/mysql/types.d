/// Structures for MySQL types not built-in to D/Phobos.
module mysql.types;
import taggedalgebraic.taggedalgebraic;
import std.datetime : DateTime, TimeOfDay, Date;
import std.typecons : Nullable;

/++
A simple struct to represent time difference.

D's std.datetime does not have a type that is closely compatible with the MySQL
interpretation of a time difference, so we define a struct here to hold such
values.
+/
struct TimeDiff
{
	bool negative;
	int days;
	ubyte hours, minutes, seconds;
}

/++
A D struct to stand for a TIMESTAMP

It is assumed that insertion of TIMESTAMP values will not be common, since in general,
such columns are used for recording the time of a row insertion, and are filled in
automatically by the server. If you want to force a timestamp value in a prepared insert,
set it into a timestamp struct as an unsigned long in the format YYYYMMDDHHMMSS
and use that for the appropriate parameter. When TIMESTAMPs are retrieved as part of
a result set it will be as DateTime structs.
+/
struct Timestamp
{
	ulong rep;
}

union _MYTYPE
{
@safeOnly:
	// blobs are const because of the indirection. In this case, it's not
	// important because nobody is going to use MySQLVal to maintain their
	// ubyte array.
	const(ubyte)[] Blob;

	typeof(null) Null;
	bool Bit;
	ubyte UByte;
	byte Byte;
	ushort UShort;
	short Short;
	uint UInt;
	int Int;
	ulong ULong;
	long Long;
	float Float;
	double Double;
	.DateTime DateTime;
	TimeOfDay Time;
	.Timestamp Timestamp;
	.Date Date;

	@disableIndex string Text;
	@disableIndex const(char)[] CText;

	// pointers
	const(bool)* BitRef;
	const(ubyte)* UByteRef;
	const(byte)* ByteRef;
	const(ushort)* UShortRef;
	const(short)* ShortRef;
	const(uint)* UIntRef;
	const(int)* IntRef;
	const(ulong)* ULongRef;
	const(long)* LongRef;
	const(float)* FloatRef;
	const(double)* DoubleRef;
	const(.DateTime)* DateTimeRef;
	const(TimeOfDay)* TimeRef;
	const(.Date)* DateRef;
	const(string)* TextRef;
	const(char[])* CTextRef;
	const(ubyte[])* BlobRef;
	const(.Timestamp)* TimestampRef;
}

alias MySQLVal = TaggedAlgebraic!_MYTYPE;

// helper to convert variants to MySQLVal. Used wherever variant is still used.
import std.variant : Variant;
package MySQLVal _toVal(Variant v)
{
	int x;
	// unfortunately, we need to use a giant switch. But hopefully people will stop using Variant, and this will go away.
	string ts = v.type.toString();
	bool isRef;
	if (ts[$-1] == '*')
	{
		ts.length = ts.length-1;
		isRef= true;
	}

	import std.meta;
	import std.traits;
	import mysql.exceptions;
	alias AllTypes = AliasSeq!(bool, byte, ubyte, short, ushort, int, uint, long, ulong, float, double, DateTime, TimeOfDay, Date, string, ubyte[], Timestamp);
	switch (ts)
	{
		static foreach(Type; AllTypes)
		{
		case fullyQualifiedName!Type:
		case "const(" ~ fullyQualifiedName!Type ~ ")":
		case "immutable(" ~ fullyQualifiedName!Type ~ ")":
		case "shared(immutable(" ~ fullyQualifiedName!Type ~ "))":
			if(isRef)
				return MySQLVal(v.get!(const(Type*)));
			else
				return MySQLVal(v.get!(const(Type)));
		}
	default:
		throw new MYX("Unsupported Database Variant Type: " ~ ts);
	}
}

/++
Use this as a stop-gap measure in order to keep Variant compatibility. Append this to any function which returns a MySQLVal until you can update your code.
+/
deprecated("Variant support is deprecated. Please switch to using MySQLVal")
Variant asVariant(MySQLVal v)
{
	return v.apply!((a) => Variant(a));
}

deprecated("Variant support is deprecated. Please switch to using MySQLVal")
Nullable!Variant asVariant(Nullable!MySQLVal v)
{
	if(v.isNull)
		return Nullable!Variant();
	return Nullable!Variant(v.get.asVariant);
}

/++
Compatibility layer for MySQLVal. These functions provide methods that
TaggedAlgebraic does not provide in order to keep functionality that was
available with Variant.
+/
bool convertsTo(T)(ref MySQLVal val)
{
	return val.apply!((a) => is(typeof(a) : T));
}

/// ditto
T get(T)(auto ref MySQLVal val)
{
	static T convert(V)(ref V v)
	{
		static if(is(V : T))
			return v;
		else
		{
			import mysql.exceptions;
			throw new MYX("Cannot get type " ~ T.stringof ~ " with MySQLVal storing type " ~ V.stringof);
		}
	}
	return val.apply!convert();
}

/// ditto
T coerce(T)(auto ref MySQLVal val)
{
	import std.conv : to;
	static T convert(V)(ref V v)
	{
		static if(is(V : T))
		{
			return v;
		}
		else static if(is(typeof(v.to!T())))
		{
			return v.to!T;
		}
		else
		{
			import mysql.exceptions;
			throw new MYX("Cannot coerce type " ~ V.stringof ~ " into type " ~ T.stringof);
		}
	}
	return val.apply!convert();
}

/// ditto
TypeInfo type(MySQLVal val) @safe pure nothrow
{
	return val.apply!((ref v) => typeid(v));
}

/// ditto
T *peek(T)(MySQLVal val)
{
	// use exact type.
	import taggedalgebraic.taggedalgebraic : get;
	if(val.hasType!T)
		return &val.get!T;
	return null;
}
