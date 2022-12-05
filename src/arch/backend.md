# Backends

An Irmin backend describes how data is persisted. By abstracting over some notion of backend, Irmin can:

 - Be very portable. See the [portability]() section for more details.
 - Be very efficient for specific datatypes. You can image providing a highly specific backend for use with your specific datatype.

There are lots of pre-existing backends including:

 - `Irmin_mem`: the in-memory backend. No data is actually persisted.
 - `Irmin_fs`: a Unix filesystem implementation where there's a natural mapping from the steps in your path (key) implementation to file paths and your contents are stored in files.
 - `Irmin_indexeddb`: a slightly more experimental backend that uses the browser's IndexedDB storage API.
 - `Irmin_pack`: another filesystem-based backend but using [pack]() files.

## Making a Backend


