This is a shell script to perform a barrier synchronization
in a k8s system over multiple hosts.

All it does is setup a coordination server with `nc`
on the `RANK=0` process and wait for the rest to dial in.
Once everyone (or a minimum) has dialed in, the leader
will broadcast a go ahead signal to all hosts. Everyone
participating will write a file lock to `COORD_DIR`
that the main container can use use similar to
`torch.dist.barrier`