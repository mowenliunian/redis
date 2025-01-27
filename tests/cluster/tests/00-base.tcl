# Check the basic monitoring and failover capabilities.

source "../tests/includes/init-tests.tcl"

if {$::simulate_error} {
    test "This test will fail" {
        fail "Simulated error"
    }
}

test "Different nodes have different IDs" {
    set ids {}
    set numnodes 0
    foreach_redis_id id {
        incr numnodes
        # Every node should just know itself.
        set nodeid [dict get [get_myself $id] id]
        assert {$nodeid ne {}}
        lappend ids $nodeid
    }
    set numids [llength [lsort -unique $ids]]
    assert {$numids == $numnodes}
}

test "It is possible to perform slot allocation" {
    cluster_allocate_slots 5
}

test "After the join, every node gets a different config epoch" {
    set trynum 60
    while {[incr trynum -1] != 0} {
        # We check that this condition is true for *all* the nodes.
        set ok 1 ; # Will be set to 0 every time a node is not ok.
        foreach_redis_id id {
            set epochs {}
            foreach n [get_cluster_nodes $id] {
                lappend epochs [dict get $n config_epoch]
            }
            if {[lsort $epochs] != [lsort -unique $epochs]} {
                set ok 0 ; # At least one collision!
            }
        }
        if {$ok} break
        after 1000
        puts -nonewline .
        flush stdout
    }
    if {$trynum == 0} {
        fail "Config epoch conflict resolution is not working."
    }
}

test "Nodes should report cluster_state is ok now" {
    assert_cluster_state ok
}

test "Sanity for CLUSTER COUNTKEYSINSLOT" {
    set reply [R 0 CLUSTER COUNTKEYSINSLOT 0]
    assert {$reply eq 0}
}

test "It is possible to write and read from the cluster" {
    cluster_write_test 0
}

test "Function no-cluster flag" {
    R 1 function load lua test {
        redis.register_function{function_name='f1', callback=function() return 'hello' end, flags={'no-cluster'}}
    }
    catch {R 1 fcall f1 0} e
    assert_match {*Can not run function on cluster, 'no-cluster' flag is set*} $e
}
