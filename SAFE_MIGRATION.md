# Migrating code to use the @safe API of mysql-native

This document describes how mysql-native is migrating to an all-@safe API and library, and how you can migrate your existing code to the new version.

First, note that the latest version of mysql, while it supports a safe API, is defaulted to supporting the original unsafe API. We highly recommend reading and following the recommendations in this document so you can start using the safe version.

## Why Safe?

*related: please see D's [Memory Safety](https://dlang.org/spec/memory-safe-d.html) page to understand what `@safe` does in D*

Since mysql-native is intended to be a key component of servers that are on the Internet, it must support the capability (even if not required) to be fully `@safe`. In addition, major web frameworks (e.g. [vibe.d](http://code.dlang.org/packages/vibe-d)) and arguably any other program is headed in this direction.

In other words, the world wants memory safe code, and libraries that provide safe interfaces and guarantees will be much more appealing. It's just not acceptable any more for the components of major development projects to be careless about memory safety.

## The Major Changes

mysql-native until now used the Phobos type `std.variant.Variant` to hold data who's type was unknown at compile time. Unfortunately, since `Variant` can hold *any* type, it must default to having a `@system` postblit/copy constructor, and a `@system` destructor. This means that just copying a `Variant`, passing it as a function parameter, or returning it from a function makes the function doing such things `@system`. This meant that we needed to move from `Variant` to a new type that allows only safe usages, but still maintained the ability to decide types at runtime.

To this end, we used the library [taggedalgebraic](http://code.dlang.org/packages/taggedalgebraic), which supports not only safe call forwarding, but also provides a much more transparent and useful API than Variant. A `TaggedAlgebraic` allows you to limit which types MySQL deals with. This allows better implicit conversion support, and more focused code. It also prevents one from passing in parameter types that are not supported and not finding that out until runtime.

The module `mysql.types` now contains a new type called `MySQLVal`, which should be, for the most part, a drop-in replacement for `Variant` in your code.

### The safe/unsafe API

In some cases, fixing memory safety in mysql-native was as simple as adding a `@safe` tag to the module or functions in the module. These functions should work just as before, but are now callable from `@safe` code.

But for the rest, to achieve full backwards compatibility, we have divided the API into two major sections -- safe and unsafe. The package `mysql.safe` will import all the safe versions of the API, the package `mysql.unsafe` will import the unsafe versions. If you import `mysql`, it will currently point at the unsafe version for backwards compatibility.

The following modules have been split into mysql.safe.*modname* and mysql.unsafe.*modname*. Importing mysql.*modname* will import the unsafe version for backwards compatibility.
* module mysql.commands
* module mysql.pool
* module mysql.result
* module mysql.prepared
* module mysql.connection

Each of these modules in unsafe mode provides the same API as the previous version of mysql. The safe version provides aliases to the original type names for the safe versions of types, and also provides the same functions as before that can be called via safe code. The one exception is in `mysql.safe.commands`, where some functions were for the deprecated `BackwardCompatPrepared`, which will eventually be removed.

If you are currently importing any of the above modules directly, or importing the `mysql` package, a first step to migration is to use the `mysql.safe` package. From there you will find that almost everything works exactly the same.

### Migrating from Variant to MySQLVal

The module `mysql.types` has been amended to contain the `MySQLVal` type. This type can hold any value type that MySQL supported originally, or a const pointer to such a type (for the purposes of prepared statements), or the value `null`. This is now the type used for all parameters to `query` and `exec` (in the safe API). The `mysql.types` import also provides compatibility shims with `Variant` such as `coerce`, `convertsTo`, `type`, `peek`, and `get` (See the documentation for [Variant](https://dlang.org/phobos/std_variant.html#.VariantN)).

You can examine all the benefits of `TaggedAlgebraic` [here](https://vibed.org/api/taggedalgebraic.taggedalgebraic/TaggedAlgebraic). In particular, the usage of the `kind` member is preferred over using the `type` shim. Note that only safe operations are allowed, so for instance `opBinary!"+"` is not allowed on pointers.

One pitfall of this migration has to do with `Variant`'s ability to represent *any* type -- including `MySQLVal`! If you have declared a variable of type `Variant`, and assign it to a `MySQLVal` result from a row or a query, it will compile, but it will NOT do what you are expecting. This will fail at runtime most likely. It is recommended before switching to the safe API to change those types to `MySQLVal` or use `auto` if possible.

The `mysql.types` module also contains a compatibility function `asVariant`, which can be used when you want to use the safe API but absolutely need a `Variant` from a `MySQLVal`. The opposite conversion is implemented, but not exposed publically since there is no compatibility issue for existing code.

One important thing to note is that the internals of mysql-native have all been switched to using `MySQLVal` instead of `Variant`. Only at the shallow API level is `Variant` used to provide the backwards compatible API. So if you do not switch, you will pay the penalty of having the library first construct a `MySQLVal` and then convert that to a `Variant` (or vice versa).

### Row and ResultRange

These two types were tied greatly to `Variant`. As such, they have been rewritten into `SafeRow` and `SafeResultRange` which use `MySQLVal` instead. Thin compatibility wrappers of `UnsafeRow` and `UnsafeResultRange` are available as well, which will convert the values to and from `Variant` as needed. Depending on which API you import `safe` or `unsafe`, these items are aliased to `Row` and `ResultRange` for source compatibility.

For this reason, you should not import both the `safe` and `unsafe` API, as you will get ambiguity errors.

However, each of these structures provides `unsafe` and `safe` conversion functions to convert between the two if absolutely necessary. In fact, most of the unsafe API calls that return an `UnsafeRow` or `UnsafeResultRange` are actually `@safe`, since the underlying implementation uses `MySQLVal`. It only becomes unsafe when you try to access a column as a `Variant`.

TODO: some examples needed

### Prepared

The `Prepared` struct contained support for setting/getting `Variant` parameters. These have been removed, and reimplemented as a `SafePrepared` struct, which uses `MySQLVal` instead. An `UnsafePrepared` wrapper has been provided, and like `Row`/`ResultSequence`, they have `unsafe`, and `safe` conversion functions.

The `mysql.safe.prepared` module will alias `Prepared` as the safe version, and the `mysql.unsafe.prepared` module will alias `Prepared` as the unsafe version.

### Connection

The Connection class itself has not changed at all, except to add @safe for everything. However, the `mysql.connection` module contained the functions to generate `Prepared` structs.

The `BackwardsCompatPrepared` struct defined in the original `mysql.connection` module is only available in the unsafe package.

### MySQLPool

`MySQLPool` has been factored into a templated type that has either a fully safe or partly safe API. The only public facing unsafe part was the user-supplied callback function to be called on every connection creation (which therefore makes `lockConnection` unsafe). The unsafe version continues to use such a callback method (and is explicitly marked `@system`), whereas the safe version requires a `@safe` callback. If you do not use this callback mechanism, it is highly recommended that you use the safe API for the pool, as there is no actual difference between the two at that point. It's also very likely that your callback actually is `@safe`, even if you do use one.

### The commands module

As previously mentioned, the `mysql.commands` module has been factored into 2 versions, a safe and unsafe version. The only differences between these two are where `Variant` is concerned. All query and exec functions that accepted `Variant` explicitly have been reimplemented in the safe version to accept `MySQLVal`. All functions that returned `Variant` have been reimplemented to return `MySQLVal`. All functions that do not deal with `Variant` are moved to the safe API, and aliased in the unsafe API. This means, as long as you do not use `Variant` explicitly, you should be able to switch over to the safe version of the API without changing your code.

TODO: some examples needed

## Future versions

The next major version of mysql-native will swap the default package imports to the safe API. In addition, all unsafe functions and types will be marked deprecated.

In a future major version (not necessarily the one after the above version), the unsafe API will be completely removed, and the safe API will take the place of the default modules. The explicit `mysql.safe` packages will remain for backwards compatibility. At this time, all uses of `Variant` will be gone.
