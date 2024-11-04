/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
struct metadata {
    bit<1> isL4S;
    bit<1> isClassic;
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
    apply {
        // Suponha que DSCP 46 (0x2E) indique L4S e 0 indique tráfego clássico
        if (hdr.ipv4.isValid() && hdr.ipv4.diffserv == 0x2E) {
            meta.isL4S = 1;
            meta.isClassic = 0;
        } else {
            meta.isL4S = 0;
            meta.isClassic = 1;
        }
    }
}

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    // Threshold constants
    const bit<19> L4S_THRESHOLD = 5000;
    const bit<19> CLASSIC_THRESHOLD = 15000;
    const bit<19> CLONE_THRESHOLD = 46;
    const bit<19> CHECK_THRESHOLD = 36;


    action mark_ecn() {
        hdr.ipv4.ecn = 3;  // Mark ECN to indicate congestion
    }

    action drop() {
        standard_metadata.drop = 1;  // Action to drop the packet
    }

    // Action to handle packet cloning and modifications
    action handle_mark() {
        bit<1> flag;
        bit<1> packetStatus;

        if (hdr.ipv4.ecn != 3) {
            if (standard_metadata.enq_qdepth > CLONE_THRESHOLD) {
                mark_ecn();
                flag = 1;
                wasMarked.write(0, flag);
            } else if (standard_metadata.enq_qdepth > CHECK_THRESHOLD) {
                wasMarked.read(packetStatus, 0);
                if (packetStatus == 1) {
                    mark_ecn();
                }
            } else {
                flag = 0;
                wasMarked.write(0, flag);
            }
        }
    }

    /* Table to help debug the code */
    table debug {
        key = {
            standard_metadata.enq_qdepth: exact;
        }
        actions = {
            NoAction;
        }
        size = 1;
        default_action=NoAction();
    }

    table l4s_queue {
        key = {
            meta.isL4S: exact;
        }
        actions = {
            handle_mark;
            NoAction;
        }
        size = 2;
        default_action = NoAction();
    }

    table classic_queue {
        key = {
            meta.isClassic: exact;
        }
        actions = {
            drop;
            handle_mark;
        }
        size = 2;
        default_action = NoAction();
    }

    apply {
         debug.apply();

        if (meta.isL4S == 1) {
            if (standard_metadata.enq_qdepth > L4S_THRESHOLD) {
                handle_mark();
            }
            l4s_queue.apply();
        }

        if (meta.isClassic == 1) {
            if (standard_metadata.enq_qdepth > CLASSIC_THRESHOLD) {
                drop();
            } else if (standard_metadata.enq_qdepth > L4S_THRESHOLD) {
                handle_mark();
            }
            classic_queue.apply();
        }
    }
}
