// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//         http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! This file exposes functions equivalent to the Python builtins module (or other builtin syntax).
//! These functions similarly operate over all types of PyObject-like values.
//!
//! See https://docs.python.org/3/library/functions.html for full reference.
const std = @import("std");
const py = @import("./pydust.zig");
const State = @import("./discovery.zig").State;
const ffi = @import("./ffi.zig");
const PyError = @import("./errors.zig").PyError;

/// Zig enum for python richcompare op int.
/// The order of enums has to match the values of ffi.Py_LT, etc
pub const CompareOp = enum {
    LT,
    LE,
    EQ,
    NE,
    GT,
    GE,
};

/// Returns a new reference to Py_NotImplemented.
pub fn NotImplemented() py.PyObject {
    // It's important that we incref the Py_NotImplemented singleton
    const notImplemented = py.PyObject{ .py = ffi.Py_NotImplemented };
    notImplemented.incref();
    return notImplemented;
}

/// Returns a new reference to Py_None.
pub fn None() py.PyObject {
    // It's important that we incref the Py_None singleton
    const none = py.PyObject{ .py = ffi.Py_None };
    none.incref();
    return none;
}

/// Returns a new reference to Py_False.
pub inline fn False() py.PyBool {
    return py.PyBool.false_();
}

/// Returns a new reference to Py_True.
pub inline fn True() py.PyBool {
    return py.PyBool.true_();
}

pub fn decref(value: anytype) void {
    py.object(value).decref();
}

pub fn incref(value: anytype) void {
    py.object(value).incref();
}

/// Checks whether a given object is callable. Equivalent to Python's callable(o).
pub fn callable(object: anytype) bool {
    const obj = try py.object(object);
    return ffi.PyCallable_Check(obj.py) == 1;
}

/// Convert an object into a dictionary. Equivalent of Python dict(o).
pub fn dict(object: anytype) !py.PyDict {
    const Dict: py.PyObject = .{ .py = @alignCast(@ptrCast(&ffi.PyDict_Type)) };
    const pyobj = try py.create(object);
    defer pyobj.decref();
    return Dict.call(py.PyDict, .{pyobj}, .{});
}

/// Checks whether a given object is None. Avoids incref'ing None to do the check.
pub fn is_none(object: anytype) bool {
    const obj = py.object(object);
    return ffi.Py_IsNone(obj.py) == 1;
}

/// Get the length of the given object. Equivalent to len(obj) in Python.
pub fn len(object: anytype) !usize {
    const length = ffi.PyObject_Length(py.object(object).py);
    if (length < 0) return PyError.PyRaised;
    return @intCast(length);
}

/// Import a module by fully-qualified name returning a PyObject.
pub fn import(module_name: [:0]const u8) !py.PyObject {
    return (try py.PyModule.import(module_name)).obj;
}

/// Import a module and return a borrowed reference to an attribute on that module.
pub fn importFrom(module_name: [:0]const u8, attr: [:0]const u8) !py.PyObject {
    const mod = try import(module_name);
    defer mod.decref();
    return try mod.get(attr);
}

/// Check if object is an instance of cls.
pub fn isinstance(object: anytype, cls: anytype) !bool {
    const pyobj = py.object(object);
    const pycls = py.object(cls);

    const result = ffi.PyObject_IsInstance(pyobj.py, pycls.py);
    if (result < 0) return PyError.PyRaised;
    return result == 1;
}

/// Return the reference count of the object.
pub fn refcnt(object: anytype) isize {
    const pyobj = py.object(object);
    return pyobj.py.ob_refcnt;
}

/// Compute a string representation of object - using str(o).
pub fn str(object: anytype) !py.PyString {
    const pyobj = py.object(object);
    return py.PyString.unchecked(.{ .py = ffi.PyObject_Str(pyobj.py) orelse return PyError.PyRaised });
}

/// Compute a string representation of object - using repr(o).
pub fn repr(object: anytype) !py.PyString {
    const pyobj = py.object(object);
    return py.PyString.unchecked(.{ .py = ffi.PyObject_Repr(pyobj.py) orelse return PyError.PyRaised });
}

/// The equivalent of Python's super() builtin. Returns a PyObject.
pub fn super(comptime Super: type, selfInstance: anytype) !py.PyObject {
    const module = State.getContaining(Super, .module);
    const imported = try import(State.getIdentifier(module).name);
    const superPyType = try imported.get(State.getIdentifier(Super).name);
    const pyObj = py.object(selfInstance);

    const superBuiltin: py.PyObject = .{ .py = @alignCast(@ptrCast(&ffi.PySuper_Type)) };
    return superBuiltin.call(.{ superPyType, pyObj }, .{});
}

pub fn tuple(object: anytype) !py.PyTuple {
    const pytuple = ffi.PySequence_Tuple(py.object(object).py) orelse return PyError.PyRaised;
    return py.PyTuple.unchecked(.{ .py = pytuple });
}

pub fn type_(object: anytype) !py.PyType {
    return .{ .obj = .{ .py = @as(
        ?*ffi.PyObject,
        @ptrCast(@alignCast(ffi.Py_TYPE(py.object(object).py))),
    ) orelse return PyError.PyRaised } };
}

// TODO(ngates): What's the easiest / cheapest way to do this?
// For now, we just check the name
pub fn self(comptime PydustType: type) !py.PyObject {
    const clsName = State.getIdentifier(PydustType).name;
    const mod = State.getContaining(PydustType, .module);
    const modName = State.getIdentifier(mod).name;

    return try importFrom(modName, clsName);
}

const testing = std.testing;

test "is_none" {
    py.initialize();
    defer py.finalize();

    const none = None();
    defer none.decref();

    try testing.expect(is_none(none));
}
