# Contents of the Store

[Irmin][] is a key-value store. The contents of the store references the value part.

This next section will cover basic concepts you might want to impose on your contents such as:

 - How to define three-way merge functions for your contents.
 - Always serialise the contents to JSON.
 - Version your content store so you can update the type in the future.

{{#include ./links.md}}}}