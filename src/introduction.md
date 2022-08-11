# Introduction

Welcome to **Real World Irmin**. This book is all about [Irmin](https://github.com/mirage/irmin).

>
> Irmin is an OCaml library for building mergeable, branchable distributed data stores.
>
> - **Built-in Snapshotting** - backup and restore
> - **Storage Agnostic** - you can use Irmin on top of your own storage layer
> - **Custom Datatypes** - (de)serialization for custom data types, derivable via ppx_irmin
> - **Highly Portable** - runs anywhere from Linux to web browsers and Xen unikernels
> - **Git Compatibility** - irmin-git uses an on-disk format that can be inspected and modified using Git
> - **Dynamic Behavior** - allows the users to define custom merge functions, use in-memory transactions 
>   (to keep track of reads as well as writes) and to define event-driven workflows using a
>   notification mechanism