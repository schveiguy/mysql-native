﻿/// Structures for MySQL types not built-in to D/Phobos.
module mysql.types;
import taggedalgebraic.taggedunion;
import std.datetime : DateTime, TimeOfDay, Date;

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
    string Text;
    ubyte[] Blob;

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
    const(ubyte[])* BlobRef;
    const(.Timestamp)* TimestampRef;
}

alias MySQLVal = TaggedUnion!_MYTYPE;
