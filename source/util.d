module util;

public import std.stdio : File;
public import std.conv : to;

import Abort = core.internal.abort;
import std.stdio;
import std.exception;
import std.conv;
import std.traits;
import std.stdio;
import std.file : thisExePath;
import std.string : lastIndexOf;

private {
    string Asset_Path = "";
}

static this() {
    Asset_Path = thisExePath();
    Asset_Path = Asset_Path[0 .. lastIndexOf(Asset_Path, '\\') + 1];
    if(Asset_Path[lastIndexOf(Asset_Path[0 .. $ - 1], '\\') .. $] == "\\bin\\") {
        Asset_Path = Asset_Path[0 .. lastIndexOf(Asset_Path[0 .. $ - 1], '\\') + 1];
    }

    Asset_Path ~= "assets/";
}

@safe nothrow:

File internal(const(char[]) filename, string mode = "rb") {
    try {
        Logger.info(Asset_Path ~ filename);
        return File(Asset_Path ~ filename, mode);
    } catch(Exception ex) {Logger.error(ex.msg); return File.init;}
}

struct Logger
{
    @trusted nothrow:

    static void info(T : string)(T info, string filename = __FILE__, size_t line = __LINE__) {
        try {
            stdout.writefln("INFO (%s|%d) : %s", filename, line, info);
        } catch(ErrnoException ex) {
            abort("Error : " ~ collectExceptionMsg(ex));
        } catch(Exception ex) {
            abort("Error : " ~ collectExceptionMsg(ex));
        }
    }

    static void info(T)(T info, string filename = __FILE__, size_t line = __LINE__) {
        T copy = info;
        try {
            Logger.info!string(to!string(copy), filename, line);
        } catch(Exception ex) {
            abort("Error : " ~ collectExceptionMsg(ex));
        }
    }

    static void warning(string warning, string filename = __FILE__, size_t line = __LINE__) {
        try {
            stdout.writefln("WARNING (%s|%d) : %s", filename, line, warning);
        } catch(ErrnoException ex) {
            abort("Error : " ~ collectExceptionMsg(ex));
        } catch(Exception ex) {
            abort("Error : " ~ collectExceptionMsg(ex));
        }
    }

    static void error(string error, string filename = __FILE__, size_t line = __LINE__) {
        try {
            stderr.writefln("ERROR (%s|%s) : %s", filename, line, error);
        } catch(Exception ex) {
        }
    }

    static void error(T)(T error, string filename = __FILE__, size_t line = __LINE__) {
        static if(is(typeof(T) == char)) {
            immutable(char)[1] c; c[0] = error;
            error(c, filename, line);
        }
    }
}

void abort(T)(T value = "", string filename = __FILE__, size_t line = __LINE__) @trusted nothrow {
    Logger.error(value, filename, line);
    try { readln(); }
    catch(Exception ex) {}
    Abort.abort("");
}
